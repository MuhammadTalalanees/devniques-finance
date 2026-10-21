-- Migration v9 (2026-10-21): investors are stored as parties
-- (kind = 'investor'), but the original parties kind CHECK only
-- allowed client/vendor/employee/other — so every investor save
-- was rejected by the database and the app silently reverted it
-- (add/edit/delete all appeared broken). Allow 'investor'.
-- Also re-asserts the v4 insert policy (any authenticated user
-- may insert a party) in case it is missing.
alter table public.parties drop constraint if exists parties_kind_check;
alter table public.parties add constraint parties_kind_check
  check (kind in ('client','vendor','employee','other','investor'));

drop policy if exists "party_insert" on public.parties;
create policy "party_insert" on public.parties
  for insert to authenticated with check (true);
