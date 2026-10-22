-- Migration v10 — WiFi aur manual attendance ke ALAG register
-- Talal ki hidayat (2026-10-21): Mark Attendance ka button sirf
-- MANUAL track ka hoga. WiFi auto entry/exit apne track par
-- chalegi — dono sessions ek hi waqt mein khulay ho sakte hain.
-- Pehle: ek user ka sirf EK open session (koi sa bhi source).
-- Ab: ek user ka ek open WIFI + ek open MANUAL session.

drop index if exists public.attendance_one_open_per_user;

create unique index if not exists attendance_one_open_wifi_per_user
  on public.attendance_sessions (user_id)
  where exit_at is null and source = 'wifi';

create unique index if not exists attendance_one_open_manual_per_user
  on public.attendance_sessions (user_id)
  where exit_at is null and source = 'manual';
