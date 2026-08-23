-- MekyyStudio V19 — complete database repair / compatibility layer
-- Run ONCE in Supabase SQL Editor after schema.sql + schema-v2.sql.
-- It is safe to run after v3-v18 too. It uses IF NOT EXISTS / DROP POLICY.
-- This fixes the common "admin sees no orders" problem caused by missing
-- v8/v9 columns and also makes the full order/chat/worker/pricing flow usable.

-- ============================================================
-- 1) Required columns
-- ============================================================

alter table public.projects add column if not exists price numeric(12,2) not null default 0;
alter table public.projects add column if not exists package_name text;
alter table public.projects add column if not exists original_price numeric(12,2);
alter table public.projects add column if not exists discount_percent numeric(5,2) not null default 0;
alter table public.projects add column if not exists refund_status text not null default 'none';
alter table public.projects add column if not exists delivered_at timestamptz;
alter table public.projects add column if not exists payment_status text not null default 'unpaid';
alter table public.projects add column if not exists payment_method text;
alter table public.projects add column if not exists delivery_url text;
alter table public.projects add column if not exists refund_requested_at timestamptz;
alter table public.projects add column if not exists payment_confirmed_at timestamptz;
alter table public.projects add column if not exists assigned_worker_id uuid references public.profiles(id) on delete set null;
alter table public.projects add column if not exists delivery_path text;
alter table public.projects add column if not exists delivery_name text;
alter table public.projects add column if not exists delivery_type text;

alter table public.messages add column if not exists attachment_path text;
alter table public.messages add column if not exists attachment_name text;
alter table public.messages add column if not exists attachment_type text;
alter table public.messages add column if not exists attachment_size bigint;

-- ============================================================
-- 2) Admin / worker helpers
-- ============================================================

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

create or replace function public.is_worker()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists(
    select 1 from public.profiles
    where id = auth.uid() and role = 'worker'
  );
$$;
revoke all on function public.is_worker() from public;
grant execute on function public.is_worker() to authenticated;

create or replace function public.my_profile_role()
returns text
language sql
security definer
set search_path = public
stable
as $$
  select role from public.profiles where id=auth.uid();
$$;
revoke all on function public.my_profile_role() from public;
grant execute on function public.my_profile_role() to authenticated;

-- ============================================================
-- 3) Profiles RLS
-- ============================================================

alter table public.profiles enable row level security;

drop policy if exists "users can view own profile" on public.profiles;
create policy "users can view own profile"
on public.profiles for select to authenticated
using (auth.uid() = id or public.is_admin());

drop policy if exists "admins can view all profiles" on public.profiles;
drop policy if exists "admins can update all profiles" on public.profiles;
create policy "admins can update all profiles"
on public.profiles for update to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists "users can update own profile" on public.profiles;
create policy "users can update own profile"
on public.profiles for update to authenticated
using (auth.uid() = id)
with check (auth.uid() = id and role = public.my_profile_role());

drop policy if exists "admins can delete profiles" on public.profiles;
create policy "admins can delete profiles"
on public.profiles for delete to authenticated
using (public.is_admin() and id <> auth.uid());

drop policy if exists "workers can view assigned customer profiles" on public.profiles;
create policy "workers can view assigned customer profiles"
on public.profiles for select to authenticated
using (
  public.is_worker()
  and exists (
    select 1 from public.projects pr
    where pr.assigned_worker_id = auth.uid()
      and pr.user_id = public.profiles.id
  )
);

-- ============================================================
-- 4) Projects RLS — this is the important admin-order fix
-- ============================================================

alter table public.projects enable row level security;

drop policy if exists "users can view own projects" on public.projects;
create policy "users can view own projects"
on public.projects for select to authenticated
using (auth.uid() = user_id or public.is_admin());

drop policy if exists "users can create own projects" on public.projects;
create policy "users can create own projects"
on public.projects for insert to authenticated
with check (auth.uid() = user_id);

drop policy if exists "customers can update own project request" on public.projects;
create policy "customers can update own project request"
on public.projects for update to authenticated
using (auth.uid() = user_id)
with check (
  auth.uid() = user_id
  and status in ('new','in_progress','delayed','awaiting_payment','payment_submitted','completed')
  and payment_status in ('unpaid','submitted','confirmed')
  and refund_status in ('none','requested')
);

drop policy if exists "admins can view all projects" on public.projects;
create policy "admins can view all projects"
on public.projects for select to authenticated
using (public.is_admin());

drop policy if exists "admins can update projects" on public.projects;
create policy "admins can update projects"
on public.projects for update to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists "workers can view assigned projects" on public.projects;
create policy "workers can view assigned projects"
on public.projects for select to authenticated
using (public.is_worker() and assigned_worker_id = auth.uid());

drop policy if exists "workers can update assigned projects" on public.projects;
create policy "workers can update assigned projects"
on public.projects for update to authenticated
using (public.is_worker() and assigned_worker_id = auth.uid())
with check (public.is_worker() and assigned_worker_id = auth.uid());

-- ============================================================
-- 5) Messages RLS
-- ============================================================

alter table public.messages enable row level security;

drop policy if exists "users can view own messages" on public.messages;
create policy "users can view own messages"
on public.messages for select to authenticated
using (
  exists (
    select 1 from public.projects pr
    where pr.id = messages.project_id
      and pr.user_id = auth.uid()
  )
  or public.is_admin()
);

drop policy if exists "users can send own messages" on public.messages;
create policy "users can send own messages"
on public.messages for insert to authenticated
with check (
  auth.uid() = sender_id
  and exists (
    select 1 from public.projects pr
    where pr.id = messages.project_id
      and pr.user_id = auth.uid()
      and pr.refund_status <> 'refunded'
  )
);

drop policy if exists "admins can view all messages" on public.messages;
create policy "admins can view all messages"
on public.messages for select to authenticated
using (public.is_admin());

drop policy if exists "admins can send messages" on public.messages;
create policy "admins can send messages"
on public.messages for insert to authenticated
with check (auth.uid() = sender_id and public.is_admin());

drop policy if exists "workers can view assigned messages" on public.messages;
create policy "workers can view assigned messages"
on public.messages for select to authenticated
using (
  public.is_worker()
  and exists (
    select 1 from public.projects pr
    where pr.id = messages.project_id
      and pr.assigned_worker_id = auth.uid()
  )
);

drop policy if exists "workers can send assigned messages" on public.messages;
create policy "workers can send assigned messages"
on public.messages for insert to authenticated
with check (
  auth.uid() = sender_id
  and public.is_worker()
  and exists (
    select 1 from public.projects pr
    where pr.id = messages.project_id
      and pr.assigned_worker_id = auth.uid()
      and pr.refund_status <> 'refunded'
  )
);

drop policy if exists "admins can delete messages" on public.messages;
create policy "admins can delete messages"
on public.messages for delete to authenticated
using (public.is_admin());

-- ============================================================
-- 6) Secure customer payment / refund RPCs
-- ============================================================

create or replace function public.submit_project_payment(
  p_project_id bigint,
  p_payment_method text
)
returns public.projects
language plpgsql
security definer
set search_path = public
as $$
declare result public.projects;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;

  update public.projects
  set payment_status = 'submitted',
      status = 'payment_submitted',
      payment_method = nullif(trim(p_payment_method),'')
  where id = p_project_id
    and user_id = auth.uid()
    and status = 'awaiting_payment'
    and refund_status = 'none'
  returning * into result;

  if result.id is null then raise exception 'This order is not ready for payment.'; end if;
  return result;
end;
$$;
revoke all on function public.submit_project_payment(bigint,text) from public;
grant execute on function public.submit_project_payment(bigint,text) to authenticated;

create or replace function public.request_project_refund(p_project_id bigint)
returns public.projects
language plpgsql
security definer
set search_path = public
as $$
declare result public.projects;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  update public.projects
  set refund_status = 'requested', refund_requested_at = now()
  where id = p_project_id
    and user_id = auth.uid()
    and status = 'delayed'
    and refund_status = 'none'
  returning * into result;
  if result.id is null then raise exception 'A refund can only be requested for a delayed order.'; end if;
  return result;
end;
$$;
revoke all on function public.request_project_refund(bigint) from public;
grant execute on function public.request_project_refund(bigint) to authenticated;

-- ============================================================
-- 7) Admin CRUD / chat / storage functions
-- ============================================================

create or replace function public.admin_delete_user(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not public.is_admin() then raise exception 'Admin only'; end if;
  if p_user_id = auth.uid() then raise exception 'You cannot delete your own admin account here'; end if;
  delete from auth.users where id = p_user_id;
end;
$$;
revoke all on function public.admin_delete_user(uuid) from public;
grant execute on function public.admin_delete_user(uuid) to authenticated;

create or replace function public.admin_clear_project_chat(p_project_id bigint)
returns void
language plpgsql
security definer
set search_path = public, storage
as $$
begin
  if not public.is_admin() then raise exception 'Admin only'; end if;
  delete from public.messages where project_id = p_project_id;
  delete from storage.objects where bucket_id='chat-files' and name like '%/' || p_project_id::text || '/%';
end;
$$;
revoke all on function public.admin_clear_project_chat(bigint) from public;
grant execute on function public.admin_clear_project_chat(bigint) to authenticated;

create or replace function public.admin_delete_project(p_project_id bigint)
returns void
language plpgsql
security definer
set search_path = public, storage
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

create or replace function public.admin_delete_storage_file(p_bucket text, p_path text)
returns void
language plpgsql
security definer
set search_path = public, storage
as $$
begin
  if not public.is_admin() then raise exception 'Admin only'; end if;
  if p_bucket not in ('chat-files','deliveries') then raise exception 'Invalid bucket'; end if;
  if p_path is null or length(trim(p_path))=0 then raise exception 'Invalid path'; end if;
  delete from storage.objects where bucket_id=p_bucket and name=p_path;
  if p_bucket='deliveries' then
    update public.projects
    set delivery_path=null, delivery_name=null, delivery_type=null
    where delivery_path=p_path;
  end if;
end;
$$;
revoke all on function public.admin_delete_storage_file(text,text) from public;
grant execute on function public.admin_delete_storage_file(text,text) to authenticated;

create or replace function public.admin_empty_storage_bucket(p_bucket text)
returns bigint
language plpgsql
security definer
set search_path = public, storage
as $$
declare deleted_count bigint;
begin
  if not public.is_admin() then raise exception 'Admin only'; end if;
  if p_bucket not in ('chat-files','deliveries') then raise exception 'Invalid bucket'; end if;
  delete from storage.objects where bucket_id=p_bucket;
  get diagnostics deleted_count = row_count;
  if p_bucket='deliveries' then
    update public.projects set delivery_path=null,delivery_name=null,delivery_type=null where delivery_path is not null;
  end if;
  return deleted_count;
end;
$$;
revoke all on function public.admin_empty_storage_bucket(text) from public;
grant execute on function public.admin_empty_storage_bucket(text) to authenticated;

-- Account deletion used by profile.html.
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

-- ============================================================
-- 8) Storage buckets + policies
-- ============================================================

insert into storage.buckets (id,name,public)
values ('chat-files','chat-files',false)
on conflict (id) do update set public=false;

insert into storage.buckets (id,name,public)
values ('deliveries','deliveries',false)
on conflict (id) do update set public=false;

-- Chat uploads: customer own folder, admin anywhere, worker assigned project.
drop policy if exists "chat files upload own folder" on storage.objects;
create policy "chat files upload own folder"
on storage.objects for insert to authenticated
with check (
  bucket_id='chat-files'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "chat files admin upload" on storage.objects;
create policy "chat files admin upload"
on storage.objects for insert to authenticated
with check (bucket_id='chat-files' and public.is_admin());

drop policy if exists "chat files worker upload" on storage.objects;
create policy "chat files worker upload"
on storage.objects for insert to authenticated
with check (
  bucket_id='chat-files'
  and public.is_worker()
  and exists (
    select 1 from public.projects pr
    where pr.id::text = (storage.foldername(name))[2]
      and pr.assigned_worker_id = auth.uid()
  )
);

drop policy if exists "chat files read own or admin" on storage.objects;
create policy "chat files read own or admin"
on storage.objects for select to authenticated
using (
  bucket_id='chat-files'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.is_admin()
    or (public.is_worker() and exists (
      select 1 from public.projects pr
      where pr.id::text=(storage.foldername(name))[2]
        and pr.assigned_worker_id=auth.uid()
    ))
  )
);

drop policy if exists "chat files delete own" on storage.objects;
create policy "chat files delete own"
on storage.objects for delete to authenticated
using (bucket_id='chat-files' and (storage.foldername(name))[1]=auth.uid()::text);

drop policy if exists "chat files delete admin" on storage.objects;
create policy "chat files delete admin"
on storage.objects for delete to authenticated
using (bucket_id='chat-files' and public.is_admin());

-- Delivery uploads / reads / deletes.
drop policy if exists "delivery files admin upload" on storage.objects;
create policy "delivery files admin upload"
on storage.objects for insert to authenticated
with check (bucket_id='deliveries' and public.is_admin());

drop policy if exists "delivery files worker upload" on storage.objects;
create policy "delivery files worker upload"
on storage.objects for insert to authenticated
with check (
  bucket_id='deliveries'
  and public.is_worker()
  and exists (
    select 1 from public.projects pr
    where pr.id::text=(storage.foldername(name))[2]
      and pr.assigned_worker_id=auth.uid()
  )
);

drop policy if exists "delivery files read allowed" on storage.objects;
create policy "delivery files read allowed"
on storage.objects for select to authenticated
using (
  bucket_id='deliveries'
  and (
    public.is_admin()
    or public.is_worker()
    or exists (
      select 1 from public.projects pr
      where pr.user_id=auth.uid() and pr.delivery_path=storage.objects.name
    )
  )
);

drop policy if exists "delivery files delete admin" on storage.objects;
create policy "delivery files delete admin"
on storage.objects for delete to authenticated
using (bucket_id='deliveries' and public.is_admin());

-- ============================================================
-- 9) Scheduled store discount
-- ============================================================

create table if not exists public.site_settings (
  key text primary key,
  value jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.site_settings enable row level security;

drop policy if exists "customers can read store discount" on public.site_settings;
drop policy if exists "public can read store discount" on public.site_settings;
create policy "public can read store discount"
on public.site_settings for select to anon, authenticated
using (key='store_discount');

drop policy if exists "admins can read store settings" on public.site_settings;
create policy "admins can read store settings"
on public.site_settings for select to authenticated
using (public.is_admin());

drop policy if exists "admins can insert store settings" on public.site_settings;
create policy "admins can insert store settings"
on public.site_settings for insert to authenticated
with check (public.is_admin());

drop policy if exists "admins can update store settings" on public.site_settings;
create policy "admins can update store settings"
on public.site_settings for update to authenticated
using (public.is_admin()) with check (public.is_admin());

insert into public.site_settings(key,value)
values ('store_discount','{"percent":0,"start":"","end":"","enabled":false}'::jsonb)
on conflict(key) do nothing;

-- ============================================================
-- 10) New-user profile trigger
-- ============================================================

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles(id,name,email,role)
  values(new.id,new.raw_user_meta_data->>'name',new.email,'customer')
  on conflict(id) do update set email=excluded.email;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

-- ============================================================
-- 11) Realtime
-- ============================================================

do $$
begin
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='messages') then
    execute 'alter publication supabase_realtime add table public.messages';
  end if;
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='projects') then
    execute 'alter publication supabase_realtime add table public.projects';
  end if;
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='profiles') then
    execute 'alter publication supabase_realtime add table public.profiles';
  end if;
end $$;

-- ============================================================
-- 12) Helpful indexes
-- ============================================================
create index if not exists projects_user_created_idx on public.projects(user_id,created_at desc);
create index if not exists projects_status_idx on public.projects(status);
create index if not exists projects_worker_idx on public.projects(assigned_worker_id);
create index if not exists messages_project_created_idx on public.messages(project_id,created_at);

-- DONE.
-- After this script, create/confirm your admin profile role:
-- update public.profiles set role='admin' where email='YOUR_ADMIN_EMAIL';
