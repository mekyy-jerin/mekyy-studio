-- MekyyStudio V20
-- Run after schema-v19-complete-fix.sql.
-- V20 removes the need for direct storage-table deletion from the Admin UI.
-- The Admin UI now uses Supabase Storage API (.remove()) and normal table deletes.

-- Admin may delete orders directly from the Admin page.
alter table public.projects enable row level security;
drop policy if exists "admins can delete projects" on public.projects;
create policy "admins can delete projects"
on public.projects for delete to authenticated
using (public.is_admin());

-- Admin may delete messages from the Admin page.
alter table public.messages enable row level security;
drop policy if exists "admins can delete messages" on public.messages;
create policy "admins can delete messages"
on public.messages for delete to authenticated
using (public.is_admin());

-- Storage deletion is intentionally handled by the Storage API in admin.html.
-- Do NOT delete rows directly from storage.objects.
-- Existing admin storage DELETE policies from V19 remain in place.

-- Keep the old RPCs from being used by the V20 UI. They are retained for
-- backwards compatibility, but the UI no longer calls them.
