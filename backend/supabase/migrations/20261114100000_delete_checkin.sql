-- Delete one of your own check-ins (a spotted aircraft, a flight or an airport visit).
-- Its photo records, salutes, comments and alerts go with it. Deleting one that doesn't exist, or isn't yours,
-- does nothing, so a repeated request is safe. The photo files in storage are not touched here.
create function public.delete_checkin(target uuid)
returns void
language sql volatile security definer set search_path = '' as $$
  delete from public.checkins where id = target and user_id = auth.uid();
$$;
revoke execute on function public.delete_checkin(uuid) from public;
grant execute on function public.delete_checkin(uuid) to authenticated;
