-- MekyyStudio V9: Admin storage manager / cleanup
-- Run AFTER schema-v8-workers-admin.sql.
-- This lets admins inspect and remove files from chat-files and deliveries.

-- Admins need delete permission for chat attachments when cleaning storage.
drop policy if exists "chat files delete admin" on storage.objects;
create policy "chat files delete admin"
on storage.objects for delete to authenticated
using (bucket_id='chat-files' and public.is_admin());

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

  delete from storage.objects
  where bucket_id=p_bucket and name=p_path;

  -- Prevent broken delivery references after an admin deletes a delivery file.
  if p_bucket='deliveries' then
    update public.projects
    set delivery_path=null,
        delivery_name=null,
        delivery_type=null
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
    update public.projects
    set delivery_path=null,
        delivery_name=null,
        delivery_type=null
    where delivery_path is not null;
  end if;

  return deleted_count;
end;
$$;
revoke all on function public.admin_empty_storage_bucket(text) from public;
grant execute on function public.admin_empty_storage_bucket(text) to authenticated;
