-- Devniques Finance migration v5: petty_cash fund/spend support.
-- Run this in the Supabase SQL Editor (project: Devniques Finance).
-- Safe to re-run.

-- 1) kind column: 'fund' = money added INTO petty cash,
--    'spend' = money spent FROM it. Old rows default to 'spend'.
alter table public.petty_cash
  add column if not exists kind text not null default 'spend';

-- 2) Allow UPDATE so entries can be edited (admin via app UI gate).
drop policy if exists "petty_cash_update_admin" on public.petty_cash;
create policy "petty_cash_update_admin" on public.petty_cash
  for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());
