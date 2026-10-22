-- Migration v4: new roles, petty_cash table, profile delete policy
-- Run this in Supabase SQL Editor.

-- 1. Drop old constraint.
ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_role_check;

-- 2. Migrate old 'staff' rows to 'add_only' FIRST (before adding constraint).
UPDATE public.profiles SET role = 'add_only' WHERE role = 'staff';

-- 3. Now add the new constraint: allow view_only, add_only, admin.
ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_role_check
  CHECK (role IN ('admin', 'add_only', 'view_only'));

-- 4. New registrations default to view_only.
ALTER TABLE public.profiles
  ALTER COLUMN role SET DEFAULT 'view_only';

-- 4. Allow admins to delete profiles.
DROP POLICY IF EXISTS "profiles_admin_delete" ON public.profiles;
CREATE POLICY "profiles_admin_delete" ON public.profiles
  FOR DELETE TO authenticated USING (public.is_admin());

-- 5. Petty cash table (small day-to-day expenses, separate section).
CREATE TABLE IF NOT EXISTS public.petty_cash (
  id TEXT PRIMARY KEY,
  amount REAL NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  date DATE NOT NULL,
  created_by TEXT NOT NULL DEFAULT '',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 6. RLS for petty_cash: everyone reads, add_only+admin write, admin deletes.
ALTER TABLE public.petty_cash ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "petty_read" ON public.petty_cash;
CREATE POLICY "petty_read" ON public.petty_cash
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "petty_insert" ON public.petty_cash;
CREATE POLICY "petty_insert" ON public.petty_cash
  FOR INSERT TO authenticated
  WITH CHECK (
    public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role IN ('admin', 'add_only')
    )
  );

DROP POLICY IF EXISTS "petty_admin_delete" ON public.petty_cash;
CREATE POLICY "petty_admin_delete" ON public.petty_cash
  FOR DELETE TO authenticated USING (public.is_admin());

-- 7. Update the handle_new_user trigger default (if it sets role explicitly).
-- The trigger inserts with default, so step 2 covers it.

-- 8. Fix parties RLS: allow any authenticated user to insert (was requiring
-- created_by which the app doesn't send for parties).
DROP POLICY IF EXISTS "party_insert" ON public.parties;
CREATE POLICY "party_insert" ON public.parties
  FOR INSERT TO authenticated WITH CHECK (true);
