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
-- 3. REALTIME: bật realtime cho bảng transactions
--    (nếu lệnh này lỗi vì publication đã có bảng, bỏ qua
--     và bật thủ công trong Dashboard > Database > Replication)
-- ---------------------------------------------------------
alter publication supabase_realtime add table public.transactions;
