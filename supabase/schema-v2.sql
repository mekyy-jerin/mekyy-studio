-- STUDIO database update
-- Run this in Supabase > SQL Editor AFTER the original schema.sql.

-- Remove old policies so this script can be re-run safely.
drop policy if exists "users can view own profile" on public.profiles;
drop policy if exists "users can view own projects" on public.projects;
drop policy if exists "users can create own projects" on public.projects;
drop policy if exists "users can view own messages" on public.messages;
drop policy if exists "users can send own messages" on public.messages;
drop policy if exists "admins can view all projects" on public.projects;
drop policy if exists "admins can update projects" on public.projects;
drop policy if exists "admins can view all messages" on public.messages;
drop policy if exists "admins can send messages" on public.messages;

-- Customer profile access.
create policy "users can view own profile"
on public.profiles for select to authenticated
using (auth.uid() = id);

-- Customers can see and create their own projects.
create policy "users can view own projects"
on public.projects for select to authenticated
using (auth.uid() = user_id);

create policy "users can create own projects"
on public.projects for insert to authenticated
with check (auth.uid() = user_id);

-- Admins can see/update every project.
create policy "admins can view all projects"
on public.projects for select to authenticated
using (
  exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  )
);

create policy "admins can update projects"
on public.projects for update to authenticated
using (
  exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  )
)
with check (
  exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  )
);

-- Customers can read their project's messages and send messages only to their own project.
create policy "users can view own messages"
on public.messages for select to authenticated
using (
  exists (
    select 1 from public.projects pr
    where pr.id = messages.project_id
      and pr.user_id = auth.uid()
  )
);

create policy "users can send own messages"
on public.messages for insert to authenticated
with check (
  auth.uid() = sender_id
  and exists (
    select 1 from public.projects pr
    where pr.id = messages.project_id
      and pr.user_id = auth.uid()
      and pr.status <> 'delivered'
  )
);

-- Admins can read and reply to all project messages.
create policy "admins can view all messages"
on public.messages for select to authenticated
using (
  exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  )
);

create policy "admins can send messages"
on public.messages for insert to authenticated
with check (
  auth.uid() = sender_id
  and exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  )
);

-- Make sure the trigger that creates customer profiles exists.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, name, email)
  values (new.id, new.raw_user_meta_data->>'name', new.email)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;

create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

-- AFTER your admin account is created, run this with your real email:
-- update public.profiles set role = 'admin' where email = 'YOUR_ADMIN_EMAIL';
