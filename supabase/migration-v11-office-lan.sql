-- Migration v11 — Office LAN ki nishaniyan (Location-off pehchan)
-- Search se sabit (Android ke apne documents): Location band ho to
-- WiFi ka NAAM (SSID/BSSID) parhna Android ki design se band hai.
-- Lekin router ki LAN nishaniyan (gateway, DHCP server, DNS, subnet)
-- Location se band NAHI hotin. App office mein ek dafa ye nishaniyan
-- seekh legi (jab naam parha jaye), phir Location band honay par bhi
-- phone unhi nishaniyon se office ko pehchan lega.
-- Prints append-only hain: update/delete ki koi policy nahi.

create table if not exists public.office_lan (
  id uuid primary key default gen_random_uuid(),
  office_id uuid not null references public.office_wifi(id) on delete cascade,
  gateway text not null default '',
  dhcp_server text not null default '',
  dns text not null default '',          -- comma-joined DNS servers
  subnet text not null default '',      -- e.g. 192.168.100.0/24
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  unique (office_id, gateway, dhcp_server, dns, subnet)
);

alter table public.office_lan enable row level security;

-- Sab logged-in users parh sakte hain (pehchan ke liye chahiye)
drop policy if exists office_lan_select on public.office_lan;
create policy office_lan_select on public.office_lan
  for select to authenticated using (true);

-- Har user sirf apne naam se print jod sakta hai
drop policy if exists office_lan_insert on public.office_lan;
create policy office_lan_insert on public.office_lan
  for insert to authenticated with check (created_by = auth.uid());

-- UPDATE / DELETE: koi policy NAHI — prints kabhi badalte/mitte nahi.
