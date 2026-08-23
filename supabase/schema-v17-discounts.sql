-- MekyyStudio V17
-- Run this ONCE in Supabase SQL Editor after schema-v3/v6.
-- Stores the admin discount centrally so every customer sees the same schedule.

create table if not exists public.site_settings (
  key text primary key,
  value jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.site_settings enable row level security;

drop policy if exists "customers can read store discount" on public.site_settings;
drop policy if exists "admins can read store settings" on public.site_settings;
drop policy if exists "admins can insert store settings" on public.site_settings;
drop policy if exists "admins can update store settings" on public.site_settings;

create policy "customers can read store discount"
on public.site_settings
for select
to authenticated
using (key = 'store_discount');

create policy "admins can read store settings"
on public.site_settings
for select
to authenticated
using (public.is_admin());

create policy "admins can insert store settings"
on public.site_settings
for insert
to authenticated
with check (public.is_admin());

create policy "admins can update store settings"
on public.site_settings
for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

insert into public.site_settings (key, value)
values (
  'store_discount',
  '{"percent":0,"start":"","end":"","enabled":false}'::jsonb
)
on conflict (key) do nothing;
