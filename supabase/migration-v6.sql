-- Devniques Finance migration v6: allow add_only users to INSERT categories.
-- Admin keeps exclusive UPDATE/DELETE. Run in Supabase SQL Editor. Safe to re-run.

-- Drop the admin-only blanket write policy on categories.
drop policy if exists "cat_write_admin" on public.categories;

-- Admins: full write (insert/update/delete).
create policy "cat_admin_write" on public.categories
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- Add-only users: insert only (no update/delete).
-- is_admin() is false for them, so the admin policy above won't match;
-- this one allows their inserts.
drop policy if exists "cat_addonly_insert" on public.categories;
create policy "cat_addonly_insert" on public.categories
  for insert to authenticated
  with check (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'add_only'
    )
  );
