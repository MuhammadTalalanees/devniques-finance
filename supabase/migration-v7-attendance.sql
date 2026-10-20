-- ============================================================
-- Devniques Finance — Migration v7: WiFi Attendance
-- Run ONCE in Supabase Dashboard > SQL Editor.
--
-- Design (locked with Talal, 2026-10-20):
--  * Entry/exit sirf employee ke MOBILE ke office-WiFi connection se.
--  * Ek user ka ek waqt mein sirf EK open session — duplicate entry
--    database level par hi impossible.
--  * Attendance record par koi edit / delete NAHI (admin bhi nahi) —
--    sirf open session par exit lag sakta hai, wo bhi sirf owner khud.
--  * Employee ko sirf APNI attendance, admin ko SAB ki.
--  * Office WiFi ki pehchan SSID + BSSID (router) se — same name wala
--    koi aur WiFi attendance nahi laga sakta.
-- ============================================================

-- ---------- office_wifi: pehchan wala table (admin manage karega) ----------
create table if not exists public.office_wifi (
  id uuid primary key default gen_random_uuid(),
  ssid text not null,
  bssid text not null unique,
  label text not null default '',
  created_at timestamptz not null default now()
);

-- ---------- attendance_sessions: ek row = ek office visit ----------
create table if not exists public.attendance_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  entry_at timestamptz not null,
  exit_at timestamptz,                       -- null = abhi office mein hai
  ssid text not null default '',
  bssid text not null default '',
  source text not null default 'wifi',       -- 'wifi' (auto) — future ke liye
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint attendance_exit_after_entry
    check (exit_at is null or exit_at > entry_at)
);

-- Ek user ka sirf EK open session (duplicate entry impossible)
create unique index if not exists attendance_one_open_per_user
  on public.attendance_sessions (user_id) where exit_at is null;

create index if not exists attendance_user_entry_idx
  on public.attendance_sessions (user_id, entry_at desc);

create index if not exists attendance_entry_idx
  on public.attendance_sessions (entry_at desc);

-- ---------- immutability: entry kabhi change nahi, band session frozen ----------
create or replace function public.attendance_freeze()
returns trigger language plpgsql as $$
begin
  if new.user_id <> old.user_id or new.entry_at <> old.entry_at then
    raise exception 'attendance entry is locked';
  end if;
  if old.exit_at is not null then
    raise exception 'attendance session is closed and locked';
  end if;
  new.updated_at := now();
  return new;
end; $$;

drop trigger if exists attendance_freeze_trg on public.attendance_sessions;
create trigger attendance_freeze_trg
  before update on public.attendance_sessions
  for each row execute function public.attendance_freeze();

-- ---------- RLS ----------
alter table public.attendance_sessions enable row level security;
alter table public.office_wifi enable row level security;

drop policy if exists attendance_select on public.attendance_sessions;
create policy attendance_select on public.attendance_sessions
  for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

-- Insert: sirf apne name par, aur entry hamesha "open" (exit pehle se nahi)
drop policy if exists attendance_insert on public.attendance_sessions;
create policy attendance_insert on public.attendance_sessions
  for insert to authenticated
  with check (user_id = auth.uid() and exit_at is null);

-- Update: sirf apni OPEN session par exit lagane ke liye (freeze trigger
-- entry_at / user_id ko change hone hi nahi dega)
drop policy if exists attendance_update on public.attendance_sessions;
create policy attendance_update on public.attendance_sessions
  for update to authenticated
  using (user_id = auth.uid() and exit_at is null)
  with check (user_id = auth.uid());

-- DELETE: koi policy NAHI = koi bhi (admin bhi) delete nahi kar sakta.

-- office_wifi: sab logged-in users parh sakte hain (Android app ko
-- pehchan ke liye chahiye), likhna/delete sirf admin.
drop policy if exists office_wifi_select on public.office_wifi;
create policy office_wifi_select on public.office_wifi
  for select to authenticated using (true);

drop policy if exists office_wifi_write on public.office_wifi;
create policy office_wifi_write on public.office_wifi
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
