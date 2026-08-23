-- STUDIO v4 ORDER FLOW
-- Run AFTER schema.sql, schema-v2.sql and schema-v3.sql.
-- New flow:
-- new -> in_progress -> delayed (optional) -> awaiting_payment -> payment_submitted -> completed
-- refund_requested -> refunded / refund_rejected can happen before completion.

alter table public.projects add column if not exists payment_status text not null default 'unpaid';
alter table public.projects add column if not exists payment_method text;
alter table public.projects add column if not exists delivery_url text;
alter table public.projects add column if not exists refund_requested_at timestamptz;
alter table public.projects add column if not exists payment_confirmed_at timestamptz;

-- Keep existing rows usable.
update public.projects
set status = 'completed',
    payment_status = 'confirmed',
    payment_confirmed_at = coalesce(payment_confirmed_at, delivered_at)
where status = 'delivered'
  and payment_status = 'unpaid';

-- Customer can update only the fields needed for a refund request or payment notice.
drop policy if exists "customers can update own project request" on public.projects;
create policy "customers can update own project request"
on public.projects for update to authenticated
using (auth.uid() = user_id)
with check (
  auth.uid() = user_id
  and (
    status in ('new','in_progress','delayed','awaiting_payment','payment_submitted','completed')
    and payment_status in ('unpaid','submitted','confirmed')
    and refund_status in ('none','requested')
  )
);

-- Admin policy from v3 is intentionally retained/replaced with helper.
drop policy if exists "admins can update projects" on public.projects;
create policy "admins can update projects"
on public.projects for update to authenticated
using (public.is_admin())
with check (public.is_admin());

-- Make admin helper available (safe to re-run).
create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists(
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;
revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;
