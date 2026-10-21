-- Migration v8 (2026-10-21): investor share % for the home
-- Investors panel. Admin enters each investor's share percent of
-- Total Raised Capital; the app calculates the amount live.
-- Applied by Talal in the Supabase SQL Editor on 2026-10-21.
alter table public.parties add column if not exists share_percent numeric;
