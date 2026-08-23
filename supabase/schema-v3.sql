-- STUDIO v3
-- Run AFTER schema.sql and schema-v2.sql.

alter table public.projects add column if not exists price numeric(12,2) not null default 0;
alter table public.projects add column if not exists refund_status text not null default 'none';
alter table public.projects add column if not exists delivered_at timestamptz;

-- Helper used by RLS policies without recursive reads of profiles.
create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists(select 1 from public.profiles where id=auth.uid() and role='admin');
$$;
revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

-- Profiles: customers edit their own name only; admins can also read all profiles.
drop policy if exists "users can update own profile" on public.profiles;
create policy "users can update own profile"
on public.profiles for update to authenticated
using (auth.uid()=id)
with check (auth.uid()=id and (role='customer' or public.is_admin()));

drop policy if exists "users can view own profile" on public.profiles;
drop policy if exists "admins can view all profiles" on public.profiles;
create policy "users can view own profile"
on public.profiles for select to authenticated
using (auth.uid()=id or public.is_admin());

-- Replace project admin policies with the helper.
drop policy if exists "admins can view all projects" on public.projects;
drop policy if exists "admins can update projects" on public.projects;
create policy "admins can view all projects"
on public.projects for select to authenticated
using (public.is_admin());
create policy "admins can update projects"
on public.projects for update to authenticated
using (public.is_admin())
with check (public.is_admin());

-- Replace message admin policies with the helper.
drop policy if exists "admins can view all messages" on public.messages;
drop policy if exists "admins can send messages" on public.messages;
create policy "admins can view all messages"
on public.messages for select to authenticated
using (public.is_admin());
create policy "admins can send messages"
on public.messages for insert to authenticated
with check (auth.uid()=sender_id and public.is_admin());

-- Secure self-delete. It requires the current authenticated session.
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  delete from auth.users where id=auth.uid();
end;
$$;
revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;
