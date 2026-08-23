-- MekyyStudio V6: chat file/image attachments
-- Run after your previous schema files.

alter table public.messages
  add column if not exists attachment_path text,
  add column if not exists attachment_name text,
  add column if not exists attachment_type text,
  add column if not exists attachment_size bigint;

-- Create a PRIVATE storage bucket in Supabase:
-- Dashboard > Storage > New bucket > Name: chat-files > Public: OFF
insert into storage.buckets (id, name, public)
values ('chat-files', 'chat-files', false)
on conflict (id) do update set public = false;

-- Users may upload only inside their own folder.
drop policy if exists "chat files upload own folder" on storage.objects;
create policy "chat files upload own folder"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'chat-files'
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- Users can read their own files. Admins can read all chat files.
drop policy if exists "chat files read own or admin" on storage.objects;
create policy "chat files read own or admin"
on storage.objects for select
to authenticated
using (
  bucket_id = 'chat-files'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or exists (
      select 1 from public.profiles
      where profiles.id = auth.uid()
      and profiles.role = 'admin'
    )
  )
);

-- Users can delete files in their own folder.
drop policy if exists "chat files delete own" on storage.objects;
create policy "chat files delete own"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'chat-files'
  and (storage.foldername(name))[1] = auth.uid()::text
);
