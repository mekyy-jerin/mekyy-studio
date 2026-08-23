-- MekyyStudio V7
-- Run AFTER schema-v6-chat-files.sql.
-- Adds secure customer payment/refund RPCs, admin uploads and Supabase Realtime.

-- ------------------------------------------------------------
-- CUSTOMER-SAFE ORDER ACTIONS
-- ------------------------------------------------------------

drop policy if exists "customers can update own project request" on public.projects;

create or replace function public.submit_project_payment(
  p_project_id bigint,
  p_payment_method text
)
returns public.projects
language plpgsql
security definer
set search_path = public
as $$
declare
  result public.projects;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  update public.projects
  set payment_status = 'submitted',
      status = 'payment_submitted',
      payment_method = p_payment_method
  where id = p_project_id
    and user_id = auth.uid()
    and status = 'awaiting_payment'
    and refund_status = 'none'
  returning * into result;

  if result.id is null then
    raise exception 'This order is not ready for payment.';
  end if;

  return result;
end;
$$;

revoke all on function public.submit_project_payment(bigint,text) from public;
grant execute on function public.submit_project_payment(bigint,text) to authenticated;


create or replace function public.request_project_refund(
  p_project_id bigint
)
returns public.projects
language plpgsql
security definer
set search_path = public
as $$
declare
  result public.projects;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  update public.projects
  set refund_status = 'requested',
      refund_requested_at = now()
  where id = p_project_id
    and user_id = auth.uid()
    and status = 'delayed'
    and refund_status = 'none'
  returning * into result;

  if result.id is null then
    raise exception 'A refund can only be requested for a delayed order.';
  end if;

  return result;
end;
$$;

revoke all on function public.request_project_refund(bigint) from public;
grant execute on function public.request_project_refund(bigint) to authenticated;


-- ------------------------------------------------------------
-- CHAT FILES
-- ------------------------------------------------------------

drop policy if exists "chat files admin upload" on storage.objects;

create policy "chat files admin upload"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'chat-files'
  and public.is_admin()
);


-- ------------------------------------------------------------
-- REALTIME
-- ------------------------------------------------------------

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'messages'
  ) then
    execute 'alter publication supabase_realtime add table public.messages';
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'projects'
  ) then
    execute 'alter publication supabase_realtime add table public.projects';
  end if;
end
$$;
