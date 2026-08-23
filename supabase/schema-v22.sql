-- MekyyStudio V22
-- Run AFTER schema-v21.sql.
-- V22: customer cancellation, reliable admin/worker chat + notes,
-- admin directory RPC, reset controls, worker access, and safe DB-only resets.

-- ------------------------------------------------------------
-- CUSTOMER CANCEL ORDER
-- ------------------------------------------------------------
create or replace function public.cancel_my_project(p_project_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_product text; v_user uuid; admin_id uuid;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  select product,user_id into v_product,v_user from public.projects
  where id=p_project_id and user_id=auth.uid() and payment_status <> 'confirmed' and status <> 'completed' and refund_status='none';
  if v_product is null then raise exception 'This order can no longer be cancelled.'; end if;
  for admin_id in select id from public.profiles where role='admin' loop
    insert into public.notifications(user_id,project_id,type,title,body)
    values(admin_id,null,'info','Order cancelled',v_product||' was cancelled by the customer.');
  end loop;
  delete from public.projects where id=p_project_id and user_id=v_user;
end;
$$;
revoke all on function public.cancel_my_project(bigint) from public;
grant execute on function public.cancel_my_project(bigint) to authenticated;

-- ------------------------------------------------------------
-- ADMIN DIRECTORY RPC
-- ------------------------------------------------------------
create or replace function public.admin_list_profiles()
returns setof public.profiles
language sql
security definer
set search_path = public
stable
as $$
  select * from public.profiles where public.is_admin() order by created_at desc;
$$;
revoke all on function public.admin_list_profiles() from public;
grant execute on function public.admin_list_profiles() to authenticated;

-- ------------------------------------------------------------
-- RELIABLE ADMIN / WORKER CHAT RPCS
-- ------------------------------------------------------------
create or replace function public.admin_send_message(
  p_project_id bigint,
  p_message text,
  p_attachment_path text default null,
  p_attachment_name text default null,
  p_attachment_type text default null,
  p_attachment_size bigint default null
)
returns public.messages
language plpgsql
security definer
set search_path = public
as $$
declare r public.messages;
begin
  if not public.is_admin() then raise exception 'Admin only'; end if;
  insert into public.messages(project_id,sender_id,message,attachment_path,attachment_name,attachment_type,attachment_size)
  values(p_project_id,auth.uid(),coalesce(nullif(trim(p_message),''),'[Attachment]'),p_attachment_path,p_attachment_name,p_attachment_type,p_attachment_size)
  returning * into r;
  return r;
end;
$$;
revoke all on function public.admin_send_message(bigint,text,text,text,text,bigint) from public;
grant execute on function public.admin_send_message(bigint,text,text,text,text,bigint) to authenticated;

create or replace function public.worker_send_message(
  p_project_id bigint,
  p_message text,
  p_attachment_path text default null,
  p_attachment_name text default null,
  p_attachment_type text default null,
  p_attachment_size bigint default null
)
returns public.messages
language plpgsql
security definer
set search_path = public
as $$
declare r public.messages;
begin
  if not public.is_worker() then raise exception 'Worker only'; end if;
  if not exists(select 1 from public.projects where id=p_project_id and assigned_worker_id=auth.uid()) then raise exception 'This order is not assigned to you'; end if;
  insert into public.messages(project_id,sender_id,message,attachment_path,attachment_name,attachment_type,attachment_size)
  values(p_project_id,auth.uid(),coalesce(nullif(trim(p_message),''),'[Attachment]'),p_attachment_path,p_attachment_name,p_attachment_type,p_attachment_size)
  returning * into r;
  return r;
end;
$$;
revoke all on function public.worker_send_message(bigint,text,text,text,text,bigint) from public;
grant execute on function public.worker_send_message(bigint,text,text,text,text,bigint) to authenticated;

-- ------------------------------------------------------------
-- WORKER NOTES RPC
-- ------------------------------------------------------------
create or replace function public.upsert_worker_note(p_project_id bigint,p_note text)
returns public.worker_notes
language plpgsql
security definer
set search_path = public
as $$
declare r public.worker_notes;
begin
  if not (public.is_admin() or (public.is_worker() and exists(select 1 from public.projects where id=p_project_id and assigned_worker_id=auth.uid()))) then
    raise exception 'Not allowed';
  end if;
  insert into public.worker_notes(project_id,note,updated_by,updated_at)
  values(p_project_id,coalesce(p_note,''),auth.uid(),now())
  on conflict(project_id) do update set note=excluded.note,updated_by=excluded.updated_by,updated_at=now()
  returning * into r;
  return r;
end;
$$;
revoke all on function public.upsert_worker_note(bigint,text) from public;
grant execute on function public.upsert_worker_note(bigint,text) to authenticated;

-- ------------------------------------------------------------
-- RESET CONTROLS: DB ONLY. Storage is intentionally handled by
-- Supabase Storage API in admin.html, never by deleting storage.objects.
-- ------------------------------------------------------------
create or replace function public.admin_reset_orders()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'Admin only'; end if;
  delete from public.projects;
end;
$$;
revoke all on function public.admin_reset_orders() from public;
grant execute on function public.admin_reset_orders() to authenticated;

create or replace function public.admin_reset_payments()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'Admin only'; end if;
  update public.projects set payment_status='unpaid',payment_method=null,payment_confirmed_at=null,
    status=case when status in ('completed','payment_submitted') then 'in_progress' else status end;
end;
$$;
revoke all on function public.admin_reset_payments() from public;
grant execute on function public.admin_reset_payments() to authenticated;

create or replace function public.admin_reset_delivery()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'Admin only'; end if;
  update public.projects set delivery_url=null,delivery_path=null,delivery_name=null,delivery_type=null,delivered_at=null
    where delivery_path is not null or delivery_url is not null;
end;
$$;
revoke all on function public.admin_reset_delivery() from public;
grant execute on function public.admin_reset_delivery() to authenticated;

create or replace function public.admin_reset_refunds()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'Admin only'; end if;
  update public.projects set refund_status='none',refund_requested_at=null where refund_status <> 'none';
end;
$$;
revoke all on function public.admin_reset_refunds() from public;
grant execute on function public.admin_reset_refunds() to authenticated;

create or replace function public.admin_reset_chat()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'Admin only'; end if;
  delete from public.messages;
end;
$$;
revoke all on function public.admin_reset_chat() from public;
grant execute on function public.admin_reset_chat() to authenticated;

-- ------------------------------------------------------------
-- CUSTOMER DELIVERY STORAGE DELETE (used only when customer cancels)
-- ------------------------------------------------------------
drop policy if exists "customer can delete own delivery on cancel" on storage.objects;
create policy "customer can delete own delivery on cancel"
on storage.objects for delete to authenticated
using (
  bucket_id='deliveries'
  and exists(
    select 1 from public.projects pr
    where pr.user_id=auth.uid()
      and pr.delivery_path=storage.objects.name
      and pr.payment_status <> 'confirmed'
  )
);

-- Ensure project/message changes are realtime.
do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='projects') then
    execute 'alter publication supabase_realtime add table public.projects';
  end if;
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='messages') then
    execute 'alter publication supabase_realtime add table public.messages';
  end if;
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='notifications') then
    execute 'alter publication supabase_realtime add table public.notifications';
  end if;
end $$;
