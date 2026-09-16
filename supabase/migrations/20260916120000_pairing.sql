-- =========================================================
-- SỔ NỢ - PAIRING: tài khoản tự đăng ký + kết bạn nợ qua mã/QR
--
-- Chạy toàn bộ file này trong Supabase Dashboard > SQL Editor.
-- File idempotent: chạy lại nhiều lần vẫn an toàn.
--
-- Nội dung:
--   1. Bảng connections      - lời mời / quan hệ pair giữa 2 người
--   2. Bảng pair_invites      - mã pairing ngắn hạn (như OTP)
--   3. Bảng contact_aliases   - tên riêng do mình đặt, chỉ mình đọc được
--   4. Hàm helper             - is_connected / can_see_profile
--   5. RPC                    - create_pair_code / redeem_pair_code
--   6. Siết quyền             - profiles (ai đọc được), transactions (chỉ pair)
--   7. Seed                   - giữ nguyên hành vi của 2 tài khoản cũ
--
-- LƯU Ý: SQL Editor chạy cả file trong MỘT transaction. Một lệnh lỗi là
-- rollback toàn bộ. Đừng dùng CREATE INDEX CONCURRENTLY (không chạy được
-- trong transaction block).
-- =========================================================

-- Không cần pgcrypto: sinh mã dùng gen_random_uuid() (pg_catalog).

-- ---------------------------------------------------------
-- 1. CONNECTIONS: mỗi cặp người chỉ có đúng 1 dòng, suốt đời.
--    Bị từ chối rồi mời lại = update status về 'pending'.
--    user_a/user_b là cột sinh sẵn (least/greatest) để unique index
--    và ON CONFLICT không phải dùng index biểu thức.
-- ---------------------------------------------------------
create table if not exists public.connections (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles (id) on delete cascade,
  addressee_id uuid not null references public.profiles (id) on delete cascade,
  user_a uuid generated always as (least(requester_id, addressee_id)) stored,
  user_b uuid generated always as (greatest(requester_id, addressee_id)) stored,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  constraint connections_different_users check (requester_id <> addressee_id),
  constraint connections_status_valid
    check (status in ('pending', 'accepted', 'declined')),
  constraint connections_pair_unique unique (user_a, user_b)
);

-- Index (least, greatest) ở trên KHÔNG phục vụ được truy vấn
-- "requester_id = tôi OR addressee_id = tôi" của policy.
create index if not exists idx_connections_requester
  on public.connections (requester_id);
create index if not exists idx_connections_addressee
  on public.connections (addressee_id);

alter table public.connections enable row level security;

drop policy if exists "connections_select_involved" on public.connections;
create policy "connections_select_involved"
  on public.connections for select
  to authenticated
  using (auth.uid() = requester_id or auth.uid() = addressee_id);

-- Chỉ người NHẬN lời mời được đồng ý / từ chối, và chỉ khi đang pending.
drop policy if exists "connections_update_by_addressee" on public.connections;
create policy "connections_update_by_addressee"
  on public.connections for update
  to authenticated
  using (auth.uid() = addressee_id and status = 'pending')
  with check (auth.uid() = addressee_id and status in ('accepted', 'declined'));

-- KHÔNG có policy insert: dòng chỉ được tạo qua RPC redeem_pair_code.

grant select on public.connections to authenticated;
revoke update on public.connections from anon, authenticated;
grant update (status) on public.connections to authenticated;

-- Trigger riêng cho connections (mốc là 'pending', không phải 'waiting'
-- như set_responded_at của transactions).
create or replace function public.connections_set_responded_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.status = 'pending' and old.status is distinct from 'pending' then
    new.responded_at = null;
  elsif old.status = 'pending' and new.status in ('accepted', 'declined') then
    new.responded_at = now();
  end if;
  return new;
end;
$$;

drop trigger if exists trg_connections_set_responded_at on public.connections;
create trigger trg_connections_set_responded_at
  before update on public.connections
  for each row execute procedure public.connections_set_responded_at();

-- ---------------------------------------------------------
-- 2. PAIR_INVITES: mã pairing của mỗi người (tối đa 1 mã sống).
--    Bật RLS và KHÔNG tạo policy nào: không ai đọc/ghi trực tiếp được,
--    chỉ vào được qua RPC security definer bên dưới.
-- ---------------------------------------------------------
create table if not exists public.pair_invites (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  code text not null unique,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_pair_invites_expires_at
  on public.pair_invites (expires_at);

alter table public.pair_invites enable row level security;
revoke all on public.pair_invites from anon, authenticated;

-- ---------------------------------------------------------
-- 3. CONTACT_ALIASES: tên riêng mình đặt cho bạn nợ.
--    Chỉ chủ sở hữu đọc/ghi được; đối phương không thấy.
-- ---------------------------------------------------------
create table if not exists public.contact_aliases (
  owner_id uuid not null references public.profiles (id) on delete cascade,
  contact_id uuid not null references public.profiles (id) on delete cascade,
  alias text not null,
  updated_at timestamptz not null default now(),
  primary key (owner_id, contact_id),
  constraint contact_aliases_different_users check (owner_id <> contact_id),
  constraint contact_aliases_alias_len
    check (char_length(btrim(alias)) between 1 and 60)
);

alter table public.contact_aliases enable row level security;

drop policy if exists "contact_aliases_owner_all" on public.contact_aliases;
create policy "contact_aliases_owner_all"
  on public.contact_aliases for all
  to authenticated
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

grant select, insert, update, delete on public.contact_aliases to authenticated;

create or replace function public.contact_alias_touch_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_contact_alias_touch on public.contact_aliases;
create trigger trg_contact_alias_touch
  before update on public.contact_aliases
  for each row execute procedure public.contact_alias_touch_updated_at();

-- ---------------------------------------------------------
-- 4. HÀM HELPER
--    security definer + search_path rỗng: policy gọi hàm này không phụ
--    thuộc RLS của bảng connections (tránh phụ thuộc vòng và tránh việc
--    siết quyền bảng connections làm hỏng policy của profiles).
-- ---------------------------------------------------------
create or replace function public.is_connected(a uuid, b uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    return false;
  end if;
  -- Không cho dùng hàm làm công cụ dò quan hệ giữa 2 người khác.
  if a is distinct from v_uid and b is distinct from v_uid then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  return exists (
    select 1
      from public.connections c
     where c.status = 'accepted'
       and c.user_a = least(a, b)
       and c.user_b = greatest(a, b)
  );
end;
$$;

create or replace function public.can_see_profile(target uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    return false;
  end if;
  if target = v_uid then
    return true;
  end if;

  -- 'declined' KHÔNG được tính: nếu tính, người từng nhận lời mời giữ
  -- quyền đọc profiles (gồm cả email) của người đã từ chối họ.
  return exists (
    select 1
      from public.connections c
     where c.status in ('pending', 'accepted')
       and c.user_a = least(v_uid, target)
       and c.user_b = greatest(v_uid, target)
  );
end;
$$;

revoke all on function public.is_connected(uuid, uuid) from public, anon;
revoke all on function public.can_see_profile(uuid) from public, anon;
grant execute on function public.is_connected(uuid, uuid) to authenticated;
grant execute on function public.can_see_profile(uuid) to authenticated;

-- ---------------------------------------------------------
-- 5. RPC
-- ---------------------------------------------------------
drop function if exists public.create_pair_code(integer);
create function public.create_pair_code(p_ttl_minutes integer default 10)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  -- Bảng chữ bỏ I, O, 0, 1 để đọc - gõ không nhầm.
  c_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_uid uuid := auth.uid();
  v_ttl integer := greatest(1, least(coalesce(p_ttl_minutes, 10), 60));
  v_expires timestamptz;
  v_bytes bytea;
  v_code text;
  v_i integer;
  v_attempt integer;
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED' using errcode = '28000';
  end if;

  delete from public.pair_invites where expires_at <= now();

  v_expires := now() + make_interval(mins => v_ttl);

  for v_attempt in 1..5 loop
    -- gen_random_uuid() là CSPRNG (pg_strong_random), nằm ở pg_catalog nên
    -- gọi được dù search_path rỗng. KHÔNG dùng gen_random_bytes của pgcrypto:
    -- extension đó nằm ở schema extensions, tên không qualify sẽ không resolve.
    -- KHÔNG dùng random() - PRNG thường có thể bị đoán trạng thái.
    -- 256 chia hết cho 32 nên phép modulo dưới đây không lệch phân phối.
    v_bytes := uuid_send(gen_random_uuid());
    v_code := '';
    for v_i in 0..7 loop
      v_code := v_code || substr(c_alphabet, get_byte(v_bytes, v_i) % 32 + 1, 1);
    end loop;

    begin
      insert into public.pair_invites (user_id, code, expires_at)
      values (v_uid, v_code, v_expires)
      on conflict (user_id) do update
        set code = excluded.code,
            expires_at = excluded.expires_at;

      return jsonb_build_object('code', v_code, 'expires_at', v_expires);
    exception
      when unique_violation then
        -- Trùng mã với người khác: sinh lại, tối đa 5 lần.
        null;
    end;
  end loop;

  raise exception 'PAIR_CODE_GENERATION_FAILED' using errcode = 'P0001';
end;
$$;

drop function if exists public.redeem_pair_code(text);
create function public.redeem_pair_code(p_code text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_code text := upper(btrim(coalesce(p_code, '')));
  v_owner uuid;
  v_status text;
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED' using errcode = '28000';
  end if;

  -- Kiểm tra hình dạng mã trước khi chạm bảng.
  if v_code !~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}$' then
    raise exception 'PAIR_CODE_INVALID' using errcode = 'P0002';
  end if;

  -- Xoá và lấy chủ mã trong cùng một câu: mã chỉ dùng được 1 lần.
  -- Nếu phần sau lỗi thì transaction rollback, mã vẫn còn.
  delete from public.pair_invites
   where code = v_code
     and expires_at > now()
  returning user_id into v_owner;

  if v_owner is null then
    raise exception 'PAIR_CODE_INVALID' using errcode = 'P0002';
  end if;

  if v_owner = v_uid then
    raise exception 'PAIR_CODE_SELF' using errcode = 'P0001';
  end if;

  select c.status into v_status
    from public.connections c
   where c.user_a = least(v_uid, v_owner)
     and c.user_b = greatest(v_uid, v_owner)
     for update;

  if v_status = 'accepted' then
    raise exception 'ALREADY_CONNECTED' using errcode = 'P0001';
  end if;

  if v_status = 'pending' then
    raise exception 'PAIR_REQUEST_EXISTS' using errcode = 'P0001';
  end if;

  insert into public.connections (requester_id, addressee_id, status)
  values (v_uid, v_owner, 'pending')
  on conflict (user_a, user_b) do update
    set requester_id = excluded.requester_id,
        addressee_id = excluded.addressee_id,
        status = 'pending',
        responded_at = null,
        created_at = now()
  returning id into v_id;

  -- Chỉ trả id, không trả tên/email (tránh dò tài khoản).
  return jsonb_build_object('connection_id', v_id, 'addressee_id', v_owner);
end;
$$;

revoke all on function public.create_pair_code(integer) from public, anon;
revoke all on function public.redeem_pair_code(text) from public, anon;
grant execute on function public.create_pair_code(integer) to authenticated;
grant execute on function public.redeem_pair_code(text) to authenticated;

-- ---------------------------------------------------------
-- 6. SIẾT QUYỀN TRÊN BẢNG CŨ
--    Có tự đăng ký thì "profiles select using (true)" nghĩa là mọi user
--    đọc được email của toàn bộ người dùng.
-- ---------------------------------------------------------
drop policy if exists "profiles_select_authenticated" on public.profiles;
drop policy if exists "profiles_select_connected" on public.profiles;
create policy "profiles_select_connected"
  on public.profiles for select
  to authenticated
  using (public.can_see_profile(id));

-- PHẢI drop policy cũ rồi tạo lại. Các policy cùng lệnh được OR với nhau,
-- nên thêm policy thứ hai sẽ không siết được gì (policy cũ vẫn thỏa).
drop policy if exists "transactions_insert_as_sender" on public.transactions;
create policy "transactions_insert_as_sender"
  on public.transactions for insert
  to authenticated
  with check (
    auth.uid() = created_by
    and public.is_connected(auth.uid(), recipient_id)
  );

-- ---------------------------------------------------------
-- 7. SEED: 2 tài khoản đang dùng phải tiếp tục giao dịch được.
--    Sinh quan hệ từ chính dữ liệu đã ngụ ý quan hệ (transactions),
--    KHÔNG nối mọi cặp profile - seed chạy lại phải không đổi kết quả.
-- ---------------------------------------------------------
insert into public.connections (requester_id, addressee_id, status, responded_at)
select distinct
       least(t.created_by, t.recipient_id),
       greatest(t.created_by, t.recipient_id),
       'accepted',
       now()
  from public.transactions t
 where t.created_by <> t.recipient_id
on conflict (user_a, user_b) do nothing;

-- ---------------------------------------------------------
-- 8. REALTIME: để người nhận thấy lời mời ngay khi đang mở sảnh.
--    Bọc DO ... EXCEPTION để chạy lại file vẫn an toàn, và để máy chủ
--    không có publication supabase_realtime cũng không làm hỏng cả file.
-- ---------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin
      alter publication supabase_realtime add table public.connections;
    exception
      when duplicate_object then null;
    end;
  end if;
end
$$;
