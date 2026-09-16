-- =========================================================
-- SỔ NỢ - Supabase schema
-- Chạy toàn bộ file này trong Supabase Dashboard > SQL Editor
-- =========================================================

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------
-- 1. PROFILES: mirror auth.users, 1-1
-- ---------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null,
  email text not null,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

drop policy if exists "profiles_select_authenticated" on public.profiles;
create policy "profiles_select_authenticated"
  on public.profiles for select
  to authenticated
  using (true);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
  on public.profiles for update
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- Tự động tạo profile khi có user mới trong auth.users
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, display_name, email)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1)),
    new.email
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ---------------------------------------------------------
-- 2. TRANSACTIONS: invoice ghi nợ / trả nợ giữa 2 người
-- ---------------------------------------------------------
create table if not exists public.transactions (
  id uuid primary key default gen_random_uuid(),
  created_by uuid not null references public.profiles (id) on delete cascade,
  recipient_id uuid not null references public.profiles (id) on delete cascade,
  type text not null check (type in ('debt', 'payment')),
  amount numeric(14, 0) not null check (amount > 0),
  description text not null default '',
  status text not null default 'waiting' check (status in ('waiting', 'accepted', 'declined')),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  constraint different_users check (created_by <> recipient_id)
);

create index if not exists idx_transactions_created_by on public.transactions (created_by);
create index if not exists idx_transactions_recipient_id on public.transactions (recipient_id);
create index if not exists idx_transactions_created_at on public.transactions (created_at desc);

alter table public.transactions enable row level security;

-- Chỉ 2 người liên quan (người tạo / người nhận) mới thấy được dòng
drop policy if exists "transactions_select_involved" on public.transactions;
create policy "transactions_select_involved"
  on public.transactions for select
  to authenticated
  using (auth.uid() = created_by or auth.uid() = recipient_id);

-- Chỉ được tạo invoice với tư cách người gửi
drop policy if exists "transactions_insert_as_sender" on public.transactions;
create policy "transactions_insert_as_sender"
  on public.transactions for insert
  to authenticated
  with check (auth.uid() = created_by);

-- Chỉ người NHẬN mới được accept/decline, và chỉ khi đang waiting
drop policy if exists "transactions_update_by_recipient" on public.transactions;
create policy "transactions_update_by_recipient"
  on public.transactions for update
  to authenticated
  using (auth.uid() = recipient_id and status = 'waiting')
  with check (auth.uid() = recipient_id and status in ('accepted', 'declined'));

-- Tự động set responded_at khi trạng thái đổi từ waiting -> accepted/declined
create or replace function public.set_responded_at()
returns trigger
language plpgsql
as $$
begin
  if new.status <> 'waiting' and old.status = 'waiting' then
    new.responded_at = now();
  end if;
  return new;
end;
$$;

drop trigger if exists trg_set_responded_at on public.transactions;
create trigger trg_set_responded_at
  before update on public.transactions
  for each row execute procedure public.set_responded_at();

-- ---------------------------------------------------------
-- 3. THEO DÕI THAY ĐỔI + BẤT BIẾN DỮ LIỆU TIỀN NỢ
--
--    Phần này trùng với supabase/migrations/20260914120000_ledger_integrity.sql
--    (giữ ở đây để cài mới chỉ cần chạy 1 file). Đã idempotent, chạy lại an toàn.
-- ---------------------------------------------------------

-- 3a. updated_at / version: client biết dữ liệu đã đổi kể từ lần sync cuối
alter table public.transactions
  add column if not exists updated_at timestamptz not null default now();

alter table public.transactions
  add column if not exists version bigint not null default 1;

update public.transactions
   set updated_at = created_at
 where version = 1
   and updated_at > created_at;

create index if not exists idx_transactions_updated_at
  on public.transactions (updated_at desc);

-- 3b. Trigger: chặn sửa field quan trọng, tự tăng version.
--     Thứ tự trigger BEFORE UPDATE là theo tên alphabet nên
--     trg_set_responded_at (mục 2) chạy trước trg_transactions_guard.
create or replace function public.transactions_guard()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if new.created_by   is distinct from old.created_by
     or new.recipient_id is distinct from old.recipient_id
     or new.type      is distinct from old.type
     or new.amount    is distinct from old.amount
     or new.description is distinct from old.description
     or new.created_at  is distinct from old.created_at then
    raise exception
      'IMMUTABLE_TRANSACTION_FIELD: created_by/recipient_id/type/amount/description/created_at không được phép sửa'
      using errcode = '42501';
  end if;

  if new.status is distinct from old.status then
    if old.status <> 'waiting' or new.status not in ('accepted', 'declined') then
      raise exception 'INVALID_STATUS_TRANSITION: % -> %', old.status, new.status
        using errcode = '42501';
    end if;
  end if;

  if old.status <> 'waiting' and new.responded_at is distinct from old.responded_at then
    raise exception 'RESPONDED_AT_IS_IMMUTABLE: không được sửa thời gian phản hồi'
      using errcode = '42501';
  end if;

  new.version := old.version + 1;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_transactions_guard on public.transactions;
create trigger trg_transactions_guard
  before update on public.transactions
  for each row execute procedure public.transactions_guard();

-- 3c. Quyền theo cột: policy update hiện tại chỉ kiểm tra recipient_id và
--     status, nên người nhận vẫn PATCH kèm amount/type/description được.
--     Thu hồi UPDATE toàn bảng, chỉ giữ cột status.
revoke update on public.transactions from anon, authenticated;
grant update (status) on public.transactions to authenticated;

-- 3d. RPC đối soát: server tự tính lại số dư + hash toàn sổ đã accepted.
create or replace function public.ledger_snapshot()
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
  with visible as (
    select id, created_by, recipient_id, type, amount, status, created_at,
           updated_at, version
      from public.transactions
  ),
  accepted as (
    select * from visible where status = 'accepted'
  )
  select jsonb_build_object(
    'total_count',    (select count(*) from visible),
    'accepted_count', (select count(*) from accepted),
    'pending_count',  (select count(*) from visible where status = 'waiting'),
    'declined_count', (select count(*) from visible where status = 'declined'),
    'max_updated_at', (select max(updated_at) from visible),
    'max_version',    (select coalesce(max(version), 0) from visible),
    'net_balance',
      (select coalesce(sum(case when created_by = auth.uid() then amount else -amount end), 0)
         from accepted),
    'ledger_hash',
      (select encode(digest(coalesce(string_agg(h, '' order by created_at, id), ''), 'sha256'), 'hex')
         from (
           select id, created_at,
                  id::text || '|' || created_by::text || '|' || recipient_id::text || '|'
                  || type || '|' || amount::text || '|' || status || '|'
                  || created_at::text as h
             from accepted
         ) parts)
  );
$$;

revoke all on function public.ledger_snapshot() from public, anon;
grant execute on function public.ledger_snapshot() to authenticated;

-- ---------------------------------------------------------
-- 4. REALTIME: bật realtime cho bảng transactions
--
--    SQL Editor chạy cả file trong một transaction, nên nếu lệnh này lỗi
--    ("already member of publication") thì TOÀN BỘ file bị rollback.
--    Vì vậy bọc trong DO ... EXCEPTION để chạy lại file vẫn an toàn.
--    Muốn bật thủ công: Dashboard > Database > Replication.
-- ---------------------------------------------------------
do $$
begin
  alter publication supabase_realtime add table public.transactions;
exception
  when duplicate_object then null;
end
$$;

-- ---------------------------------------------------------
-- 5. PAIRING: tài khoản tự đăng ký + kết bạn nợ qua mã/QR
--
--    Phần này trùng với supabase/migrations/20260916120000_pairing.sql
--    (giữ ở đây để cài mới chỉ cần chạy 1 file). Đã idempotent.
--    Đặt ở cuối file vì policy của mục này thay thế policy ở mục 1 và 2.
-- ---------------------------------------------------------

-- 5a. CONNECTIONS: mỗi cặp người chỉ có đúng 1 dòng, suốt đời.
--     Bị từ chối rồi mời lại = update status về 'pending'.
--     user_a/user_b là cột sinh sẵn (least/greatest) để unique index
--     và ON CONFLICT không phải dùng index biểu thức.
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

-- 5b. PAIR_INVITES: mã pairing của mỗi người (tối đa 1 mã sống).
--     Bật RLS và KHÔNG tạo policy nào: không ai đọc/ghi trực tiếp được,
--     chỉ vào được qua RPC security definer.
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

-- 5c. CONTACT_ALIASES: tên riêng mình đặt cho bạn nợ.
--     Chỉ chủ sở hữu đọc/ghi được; đối phương không thấy.
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

-- 5d. HÀM HELPER
--     security definer + search_path rỗng: policy gọi hàm này không phụ
--     thuộc RLS của bảng connections (tránh phụ thuộc vòng và tránh việc
--     siết quyền bảng connections làm hỏng policy của profiles).
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

-- 5e. RPC
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

-- 5f. SIẾT QUYỀN TRÊN BẢNG CŨ
--     Có tự đăng ký thì "profiles select using (true)" nghĩa là mọi user
--     đọc được email của toàn bộ người dùng.
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

-- 5g. SEED: 2 tài khoản đang dùng phải tiếp tục giao dịch được.
--     Sinh quan hệ từ chính dữ liệu đã ngụ ý quan hệ (transactions),
--     KHÔNG nối mọi cặp profile - seed chạy lại phải không đổi kết quả.
insert into public.connections (requester_id, addressee_id, status, responded_at)
select distinct
       least(t.created_by, t.recipient_id),
       greatest(t.created_by, t.recipient_id),
       'accepted',
       now()
  from public.transactions t
 where t.created_by <> t.recipient_id
on conflict (user_a, user_b) do nothing;

-- 5h. REALTIME: để người nhận thấy lời mời ngay khi đang mở sảnh.
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
