-- Opening a row in the activity inbox marks that row read. Only the caller's own rows are touched.
create function public.mark_notification_read(p_id uuid) returns void
language sql security definer set search_path = '' as $$
  update public.notifications n set read_at = now()
  where auth.uid() is not null and n.id = p_id and n.recipient = auth.uid() and n.read_at is null;
$$;

revoke execute on function public.mark_notification_read(uuid) from public, anon;
grant execute on function public.mark_notification_read(uuid) to authenticated;
