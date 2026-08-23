-- MekyyStudio V8: workers, assignments, delivery files, admin CRUD and chat management
-- Run AFTER schema-v7-live-chat-payment.sql.

-- ------------------------------------------------------------
-- WORKERS / ASSIGNMENTS
-- ------------------------------------------------------------
alter table public.projects add column if not exists assigned_worker_id uuid references public.profiles(id) on delete set null;
alter table public.projects add column if not exists delivery_path text;
alter table public.projects add column if not exists delivery_name text;
alter table public.projects add column if not exists delivery_type text;

-- ------------------------------------------------------------
-- WORKER / ADMIN HELPER FUNCTIONS
-- ------------------------------------------------------------
create or replace function public.is_worker()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists(select 1 from public.profiles where id=auth.uid() and role='worker');
$$;
revoke all on function public.is_worker() from public;
grant execute on function public.is_worker() to authenticated;

create or replace function public.admin_delete_user(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not public.is_admin() then raise exception 'Admin only'; end if;
  if p_user_id = auth.uid() then raise exception 'You cannot delete your own admin account here'; end if;
  delete from auth.users where id=p_user_id;
end;
$$;
revoke all on function public.admin_delete_user(uuid) from public;
grant execute on function public.admin_delete_user(uuid) to authenticated;

create or replace function public.admin_clear_project_chat(p_project_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'Admin only'; end if;
  delete from public.messages where project_id=p_project_id;
  delete from storage.objects where bucket_id='chat-files' and name like '%/' || p_project_id::text || '/%';
end;
$$;
revoke all on function public.admin_clear_project_chat(bigint) from public;
grant execute on function public.admin_clear_project_chat(bigint) to authenticated;

-- ------------------------------------------------------------
-- PROJECT RLS: workers can see/update only assigned work
-- ------------------------------------------------------------
drop policy if exists "workers can view assigned projects" on public.projects;
create policy "workers can view assigned projects"
on public.projects for select to authenticated
using (assigned_worker_id=auth.uid() and public.is_worker());

drop policy if exists "workers can update assigned projects" on public.projects;
create policy "workers can update assigned projects"
on public.projects for update to authenticated
using (assigned_worker_id=auth.uid() and public.is_worker())
with check (assigned_worker_id=auth.uid() and public.is_worker());

-- ------------------------------------------------------------
-- MESSAGE RLS: assigned workers can chat with their customers
-- ------------------------------------------------------------
drop policy if exists "workers can view assigned messages" on public.messages;
create policy "workers can view assigned messages"
on public.messages for select to authenticated
using (
  public.is_worker()
  and exists(
    select 1 from public.projects pr
    where pr.id=messages.project_id and pr.assigned_worker_id=auth.uid()
  )
);

drop policy if exists "workers can send assigned messages" on public.messages;
create policy "workers can send assigned messages"
on public.messages for insert to authenticated
with check (
  auth.uid()=sender_id
  and public.is_worker()
  and exists(
    select 1 from public.projects pr
    where pr.id=messages.project_id and pr.assigned_worker_id=auth.uid()
      and pr.refund_status <> 'refunded'
  )
);

drop policy if exists "admins can delete messages" on public.messages;
create policy "admins can delete messages"
on public.messages for delete to authenticated
using (public.is_admin());

-- ------------------------------------------------------------
-- DELIVERY FILE STORAGE
-- ------------------------------------------------------------
insert into storage.buckets (id,name,public)
values ('deliveries','deliveries',false)
on conflict (id) do update set public=false;

drop policy if exists "delivery files admin upload" on storage.objects;
create policy "delivery files admin upload"
on storage.objects for insert to authenticated
with check (bucket_id='deliveries' and public.is_admin());

drop policy if exists "delivery files worker upload" on storage.objects;
create policy "delivery files worker upload"
on storage.objects for insert to authenticated
with check (bucket_id='deliveries' and public.is_worker());

drop policy if exists "delivery files read allowed" on storage.objects;
create policy "delivery files read allowed"
on storage.objects for select to authenticated
using (
  bucket_id='deliveries'
  and (
    public.is_admin()
    or public.is_worker()
    or exists(
      select 1 from public.projects pr
      where pr.user_id=auth.uid()
        and pr.delivery_path=storage.objects.name
    )
  )
);

drop policy if exists "delivery files delete admin" on storage.objects;
create policy "delivery files delete admin"
on storage.objects for delete to authenticated
using (bucket_id='deliveries' and public.is_admin());

-- Workers need to upload chat files too.
drop policy if exists "chat files worker upload" on storage.objects;
create policy "chat files worker upload"
on storage.objects for insert to authenticated
with check (
  bucket_id='chat-files'
  and public.is_worker()
  and exists(
    select 1 from public.projects pr
    where pr.id::text=(storage.foldername(name))[2]
      and pr.assigned_worker_id=auth.uid()
  )
);

-- ------------------------------------------------------------
-- REALTIME
-- ------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public' and tablename='profiles'
  ) then execute 'alter publication supabase_realtime add table public.profiles'; end if;
end $$;

-- Admin profile management.
drop policy if exists "admins can update all profiles" on public.profiles;
create policy "admins can update all profiles"
on public.profiles for update to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists "admins can delete profiles" on public.profiles;
create policy "admins can delete profiles"
on public.profiles for delete to authenticated
using (public.is_admin() and id <> auth.uid());

create or replace function public.admin_delete_project(p_project_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'Admin only'; end if;
  delete from public.messages where project_id=p_project_id;
  delete from public.projects where id=p_project_id;
  delete from storage.objects where bucket_id='chat-files' and name like '%/' || p_project_id::text || '/%';
  delete from storage.objects where bucket_id='deliveries' and name like '%/' || p_project_id::text || '/%';
end;
$$;
revoke all on function public.admin_delete_project(bigint) from public;
grant execute on function public.admin_delete_project(bigint) to authenticated;

drop policy if exists "workers can view assigned customer profiles" on public.profiles;
create policy "workers can view assigned customer profiles"
on public.profiles for select to authenticated
using (
  public.is_worker()
  and exists(
    select 1 from public.projects pr
    where pr.assigned_worker_id=auth.uid() and pr.user_id=profiles.id
  )
);

drop policy if exists "chat files worker read assigned" on storage.objects;
create policy "chat files worker read assigned"
on storage.objects for select to authenticated
using (
  bucket_id='chat-files'
  and public.is_worker()
  and exists(
    select 1 from public.projects pr
    where pr.id::text=(storage.foldername(name))[2]
      and pr.assigned_worker_id=auth.uid()
  )
);
