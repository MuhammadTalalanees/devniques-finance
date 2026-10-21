-- ============================================================
-- Devniques Finance — Supabase schema
-- Run this ONCE in Supabase Dashboard > SQL Editor
-- ============================================================

create extension if not exists "pgcrypto";

-- ---------- profiles (app users + roles) ----------
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  name text not null default '',
  role text not null default 'staff' check (role in ('admin','staff')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- auto-create a 'staff' profile whenever someone signs up
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, name)
  values (new.id, new.email, coalesce(new.raw_user_meta_data ->> 'name', ''));
  return new;
end; $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users for each row execute function public.handle_new_user();

-- helper used by RLS policies (bypasses RLS itself)
create or replace function public.is_admin()
returns boolean language sql security definer set search_path = public stable as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;

-- ---------- categories ----------
create table public.categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  type text not null check (type in ('income','expense','both')),
  color text not null default '#5b9dff',
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------- parties (clients / vendors / employees) ----------
create table public.parties (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  kind text not null check (kind in ('client','vendor','employee','other','investor')),
  phone text,
  email text,
  notes text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------- transactions ----------
-- type: 'debit' = money out (expense), 'credit' = money in (general),
--       'investment' = money in from an investor (investor column set)
create table public.transactions (
  id uuid primary key default gen_random_uuid(),
  type text not null check (type in ('debit','credit','investment')),
  amount numeric(14,2) not null check (amount > 0),
  category_id uuid references public.categories(id) on delete set null,
  party_id uuid references public.parties(id) on delete set null,
  investor text not null default '',
  date date not null default CURRENT_DATE,
  description text not null default '',
  payment_method text not null default 'Cash'
    check (payment_method in ('Cash','Bank','Card','Online','Other')),
  receipt_url text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------- audit log (written by triggers, tamper-resistant) ----------
create table public.audit_log (
  id uuid primary key default gen_random_uuid(),
  actor uuid,
  action text not null,
  table_name text not null,
  record_id uuid,
  detail jsonb,
  created_at timestamptz not null default now()
);

create or replace function public.audit_trigger()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.audit_log (actor, action, table_name, record_id, detail)
  values (auth.uid(), TG_OP, TG_TABLE_NAME, coalesce(new.id, old.id),
          jsonb_build_object('old', to_jsonb(old), 'new', to_jsonb(new)));
  return coalesce(new, old);
end; $$;

drop trigger if exists audit_transactions on public.transactions;
create trigger audit_transactions
  after insert or update or delete on public.transactions
  for each row execute function public.audit_trigger();

drop trigger if exists audit_categories on public.categories;
create trigger audit_categories
  after insert or update or delete on public.categories
  for each row execute function public.audit_trigger();

drop trigger if exists audit_parties on public.parties;
create trigger audit_parties
  after insert or update or delete on public.parties
  for each row execute function public.audit_trigger();

-- ---------- auto-bump updated_at ----------
create or replace function public.bump_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end; $$;

do $$
declare t text;
begin
  foreach t in array array['profiles','categories','parties','transactions'] loop
    execute format('drop trigger if exists bump_%s on public.%I', t, t);
    execute format('create trigger bump_%s before update on public.%I for each row execute function public.bump_updated_at()', t, t);
  end loop;
end $$;

-- ============================================================
-- ROW LEVEL SECURITY
-- admin  = add + edit + delete + manage users
-- staff  = add only (no edit, no delete) — enforced HERE
-- ============================================================
alter table public.profiles      enable row level security;
alter table public.categories    enable row level security;
alter table public.parties       enable row level security;
alter table public.transactions  enable row level security;
alter table public.audit_log     enable row level security;

-- profiles
create policy "profiles_read_own_or_admin" on public.profiles
  for select to authenticated using (auth.uid() = id or public.is_admin());
create policy "profiles_admin_update" on public.profiles
  for update to authenticated using (public.is_admin());
-- (inserts come from the handle_new_user trigger, which bypasses RLS)

-- categories: everyone reads, only admin writes
create policy "cat_read" on public.categories
  for select to authenticated using (true);
create policy "cat_write_admin" on public.categories
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- parties: everyone reads, anyone adds, only admin edits/deletes
create policy "party_read" on public.parties
  for select to authenticated using (true);
create policy "party_insert" on public.parties
  for insert to authenticated with check (created_by = auth.uid());
create policy "party_admin_write" on public.parties
  for update to authenticated using (public.is_admin());
create policy "party_admin_delete" on public.parties
  for delete to authenticated using (public.is_admin());

-- transactions: everyone reads, anyone adds, only admin edits/deletes
create policy "txn_read" on public.transactions
  for select to authenticated using (true);
create policy "txn_insert" on public.transactions
  for insert to authenticated with check (created_by = auth.uid());
create policy "txn_update_admin" on public.transactions
  for update to authenticated using (public.is_admin());
create policy "txn_delete_admin" on public.transactions
  for delete to authenticated using (public.is_admin());

-- audit log: admin reads, nobody writes directly (triggers only)
create policy "audit_admin_read" on public.audit_log
  for select to authenticated using (public.is_admin());

-- ---------- receipt storage ----------
insert into storage.buckets (id, name, public)
values ('receipts', 'receipts', true)
on conflict (id) do nothing;

create policy "receipt_read" on storage.objects
  for select to authenticated using (bucket_id = 'receipts');
create policy "receipt_insert" on storage.objects
  for insert to authenticated with check (bucket_id = 'receipts');
create policy "receipt_delete_admin" on storage.objects
  for delete to authenticated using (bucket_id = 'receipts' and public.is_admin());

-- ============================================================
-- SEED: default categories (mirrors the Devniques Expense Tracker)
-- ============================================================
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

-- ============================================================
-- AFTER SIGNUP: promote yourself to admin (replace the email)
-- ============================================================
-- update public.profiles set role = 'admin' where email = 'you@devniques.com';
