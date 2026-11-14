-- A fourth sharing level between Friends and Public: Followers. Anyone who follows you sees the check-in, and can get
-- alerts for it, without you following back. Friends stays mutual, Public stays open (with its delay and the private
-- profile rule). A private profile still shows check-ins only to friends.

alter table public.checkins drop constraint if exists checkins_visibility_check;
alter table public.checkins add constraint checkins_visibility_check
  check (visibility in ('public', 'followers', 'friends', 'private'));
alter table public.profiles drop constraint if exists profiles_default_visibility_check;
alter table public.profiles add constraint profiles_default_visibility_check
  check (default_visibility in ('public', 'followers', 'friends', 'private'));

create or replace function private.can_view_checkin_row(author uuid, row_visibility text, occurred timestamptz)
returns boolean
language sql stable security definer set search_path = '' as $$
  select case
    when auth.uid() = author then true
    when coalesce(private.is_blocked(auth.uid(), author), false) then false
    when row_visibility = 'friends' then coalesce(private.are_friends(auth.uid(), author), false)
    when row_visibility = 'followers' then
      coalesce(private.are_friends(auth.uid(), author), false)
      or (exists (select 1 from public.follows f where f.follower = auth.uid() and f.followee = author)
          and coalesce((select not p.is_private from public.profiles p where p.id = author), false))
    when row_visibility = 'public' then
      coalesce(private.are_friends(auth.uid(), author), false)
      or coalesce((
        select not p.is_private
           and occurred + make_interval(mins => p.post_delay_minutes) <= now()
        from public.profiles p where p.id = author
      ), false)
    else false
  end;
$$;

create or replace function private.can_view_checkin_row_as(viewer uuid, author uuid, row_visibility text, occurred timestamptz)
returns boolean
language sql stable security definer set search_path = '' as $$
  select case
    when viewer = author then true
    when coalesce(private.is_blocked(viewer, author), false) then false
    when row_visibility = 'friends' then coalesce(private.are_friends(viewer, author), false)
    when row_visibility = 'followers' then
      coalesce(private.are_friends(viewer, author), false)
      or (exists (select 1 from public.follows f where f.follower = viewer and f.followee = author)
          and coalesce((select not p.is_private from public.profiles p where p.id = author), false))
    when row_visibility = 'public' then
      coalesce(private.are_friends(viewer, author), false)
      or coalesce((
        select not p.is_private
           and occurred + make_interval(mins => p.post_delay_minutes) <= now()
        from public.profiles p where p.id = author
      ), false)
    else false
  end;
$$;

-- The functions that check the list of levels (sync_checkins, set_sharing) get the new level. Their text is patched
-- in place so the long sync function isn't copied again.
do $$
declare
  fn record;
  def text;
begin
  for fn in
    select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private') and p.prosrc like '%(''public'', ''friends'', ''private'')%'
  loop
    def := pg_get_functiondef(fn.oid);
    execute replace(def, '(''public'', ''friends'', ''private'')', '(''public'', ''followers'', ''friends'', ''private'')');
  end loop;
end;
$$;
