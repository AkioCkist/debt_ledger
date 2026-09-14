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
