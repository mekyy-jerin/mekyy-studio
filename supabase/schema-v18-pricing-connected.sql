-- MekyyStudio V18 — connect public pricing display to the scheduled discount.
-- Run AFTER schema-v17-discounts.sql.
-- Anonymous users can read ONLY store_discount; writes remain admin-only.

drop policy if exists "customers can read store discount" on public.site_settings;

create policy "public can read store discount"
on public.site_settings
for select
to anon, authenticated
using (key = 'store_discount');
