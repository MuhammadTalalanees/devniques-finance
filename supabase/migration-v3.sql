-- ============================================================
-- Devniques Finance — v3 migration (Expense-Tracker model)
-- Run this ONCE in Supabase Dashboard > SQL Editor
-- (only if you already ran the original schema.sql before)
-- ============================================================

-- 1) allow the new entry types: debit / credit / investment
alter table public.transactions
  drop constraint if exists transactions_type_check;
alter table public.transactions
  add constraint transactions_type_check
  check (type in ('debit','credit','investment'));

-- 2) investor name column for 'investment' entries
alter table public.transactions
  add column if not exists investor text not null default '';

-- 3) replace the old 10 seed categories with the 8 tracker categories
delete from public.categories where name in
  ('Client Payments','Other Income','Salaries','Office Rent','Utilities',
   'Marketing','Software & Tools','Travel','Office Supplies','Miscellaneous');

insert into public.categories (name, type, color) values
  ('Vendor Payments',      'expense', '#ef4444'),
  ('Rent & Utilities',     'expense', '#fb923c'),
  ('Office Setup & Maint', 'expense', '#fbbf24'),
  ('IT & Equipment',       'expense', '#5b9dff'),
  ('Salaries & Wages',     'expense', '#f87171'),
  ('Food & Entertainment', 'expense', '#a78bfa'),
  ('Office Running',       'expense', '#4ade80'),
  ('Other',                'expense', '#94a3b8')
on conflict (name) do nothing;
