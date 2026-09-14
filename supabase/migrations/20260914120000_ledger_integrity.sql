-- =========================================================
-- SỔ NỢ - migration: theo dõi thay đổi + bất biến dữ liệu tiền nợ
-- (Đã tối ưu cho Supabase)
--
-- Chạy SAU khi đã chạy schema chính.
-- File này idempotent: chạy lại nhiều lần không lỗi, không mất dữ liệu.
-- =========================================================

-- ---------------------------------------------------------
-- 0. Kích hoạt Extension pgcrypto (Yêu cầu cho Supabase)
-- ---------------------------------------------------------
create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------
-- 1. Cột theo dõi thay đổi
-- ---------------------------------------------------------
alter table public.transactions
  add column if not exists updated_at timestamptz not null default now();

alter table public.transactions
  add column if not exists version bigint not null default 1;

-- Backfill cho dữ liệu cũ: coi lần thay đổi cuối là lúc tạo.
-- Chỉ chạm các dòng chưa từng bị update (version = 1) nên chạy lại vẫn an toàn.
update public.transactions
   set updated_at = created_at
 where version = 1
   and updated_at > created_at;

create index if not exists idx_transactions_updated_at
  on public.transactions (updated_at desc);

-- ---------------------------------------------------------
-- 2. Trigger bất biến + tự tăng version
-- ---------------------------------------------------------
create or replace function public.transactions_guard()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  -- (a) Các field mô tả "khoản nợ" không bao giờ được đổi sau khi tạo.
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

  -- (b) Trạng thái chỉ được đi 1 bước: waiting -> accepted | declined.
  if new.status is distinct from old.status then
    if old.status <> 'waiting' or new.status not in ('accepted', 'declined') then
      raise exception 'INVALID_STATUS_TRANSITION: % -> %', old.status, new.status
        using errcode = '42501';
    end if;
  end if;

  -- (c) responded_at là dấu vết phản hồi, sau khi chốt thì không đổi nữa.
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

-- ---------------------------------------------------------
-- 3. Column privilege: chặn ở tầng quyền, không chỉ ở tầng policy
-- ---------------------------------------------------------
revoke update on public.transactions from anon, authenticated;
grant update (status) on public.transactions to authenticated;

-- ---------------------------------------------------------
-- 4. RPC đối soát phía server
-- ---------------------------------------------------------
create or replace function public.ledger_snapshot()
returns jsonb
language sql
stable
security invoker
-- Thêm 'extensions' vào search_path để gọi hàm digest() từ pgcrypto
set search_path = public, extensions
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
      (select encode(extensions.digest(coalesce(string_agg(h, '' order by created_at, id), ''), 'sha256'), 'hex')
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