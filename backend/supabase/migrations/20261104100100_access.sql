-- Access rules (docs/CONCEPT.md §6.1, §8, §11.3).
--
-- Everything is denied unless granted below. Table grants decide which columns a client
-- role can touch at all; policies decide which rows. Writes with business logic (check-ins,
-- badges, purchases, reports) have no client grants: they go through Edge Functions.
--
-- Visibility of a check-in to another user:
-- - private: nobody else.
-- - friends: mutual follows only.
-- - public: everyone, after the author's post delay. If the author's profile is private,
--   it is treated as friends-only. Friends don't wait for the delay.
-- A block in either direction hides everything.

revoke all on all tables in schema public from anon, authenticated;
revoke all on all routines in schema public from public, anon, authenticated;
alter default privileges for role postgres in schema public
  revoke all on tables from anon, authenticated;
-- This covers Supabase's per-schema grants only. Postgres also gives PUBLIC execute on every new
-- function by a global default, so each function below revokes that itself. The tests fail if
-- a function in public is left open.
alter default privileges for role postgres in schema public
  revoke all on routines from anon, authenticated;

-- Helpers are in a schema the API doesn't expose. They are security definer so policies
-- can read other tables without recursing through those tables' own policies.
create schema private;
grant usage on schema private to anon, authenticated;

create function private.is_blocked(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.blocks
    where (blocker = a and blocked = b) or (blocker = b and blocked = a)
  );
$$;

create function private.are_friends(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.follows where follower = a and followee = b)
     and exists (select 1 from public.follows where follower = b and followee = a);
$$;

-- Whether the current user may see a profile's activity, badges and connections.
create function private.can_view_profile_content(target uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select auth.uid() = target or (
    not coalesce(private.is_blocked(auth.uid(), target), false)
    and (
      not coalesce((select is_private from public.profiles where id = target), true)
      or coalesce(private.are_friends(auth.uid(), target), false)
    )
  );
$$;

create function private.can_view_checkin_row(author uuid, row_visibility text, occurred timestamptz)
returns boolean
language sql stable security definer set search_path = '' as $$
  select case
    when auth.uid() = author then true
    when coalesce(private.is_blocked(auth.uid(), author), false) then false
    when row_visibility = 'friends' then coalesce(private.are_friends(auth.uid(), author), false)
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

create function private.can_view_checkin(target uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((
    select private.can_view_checkin_row(c.user_id, c.visibility, c.occurred_at)
    from public.checkins c where c.id = target
  ), false);
$$;

grant execute on all functions in schema private to anon, authenticated;

-- Every new account gets a profile and notification settings. The generated username can be
-- changed during onboarding.
create function private.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, username)
  values (new.id, 'user_' || right(replace(new.id::text, '-', ''), 25));
  insert into public.notification_prefs (user_id) values (new.id);
  return new;
end;
$$;
revoke execute on function private.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- A block ends any follow relationship in both directions.
create function private.handle_new_block() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  delete from public.follows
  where (follower = new.blocker and followee = new.blocked)
     or (follower = new.blocked and followee = new.blocker);
  return new;
end;
$$;
revoke execute on function private.handle_new_block() from public, anon, authenticated;

create trigger on_block_created
  after insert on public.blocks
  for each row execute function private.handle_new_block();

-- Enable RLS on every table, including any that a policy below forgets.
do $$
declare
  t record;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', t.tablename);
  end loop;
end;
$$;

-- Public reference data and configuration
grant select on public.airports, public.aircraft_types, public.operators, public.aircraft,
  public.badges, public.app_config, public.refdata_snapshots to anon, authenticated;

create policy "public read" on public.airports for select to anon, authenticated using (true);
create policy "public read" on public.aircraft_types for select to anon, authenticated using (true);
create policy "public read" on public.operators for select to anon, authenticated using (true);
create policy "public read" on public.aircraft for select to anon, authenticated using (true);
create policy "public read" on public.badges for select to anon, authenticated using (true);
create policy "public read" on public.app_config for select to anon, authenticated using (true);
create policy "public read" on public.refdata_snapshots for select to anon, authenticated using (true);

-- Profiles: home_airport and post_delay_minutes are only available through get_profile.
grant select (id, username, display_name, avatar_url, xp, is_private, created_at)
  on public.profiles to anon, authenticated;
grant update (username, display_name, avatar_url, home_airport, is_private, post_delay_minutes)
  on public.profiles to authenticated;

create policy "read unless blocked" on public.profiles for select to anon, authenticated
  using (not coalesce(private.is_blocked((select auth.uid()), id), false));
create policy "update own" on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

create function public.get_profile(target uuid)
returns table (id uuid, home_airport integer, post_delay_minutes integer)
language sql stable security definer set search_path = '' as $$
  select
    p.id,
    case when private.can_view_profile_content(p.id) then p.home_airport end,
    case when p.id = auth.uid() then p.post_delay_minutes end
  from public.profiles p
  where p.id = target and not coalesce(private.is_blocked(auth.uid(), p.id), false);
$$;
revoke execute on function public.get_profile(uuid) from public;
grant execute on function public.get_profile(uuid) to anon, authenticated;

-- Check-ins: the location column is never granted, so raw GPS can't be read through the API.
grant select (id, user_id, kind, occurred_at, created_at, aircraft_id, type_icao, operator_id,
              airport_id, spot_location_id, phase, tags, note, rating, session_id, verification,
              visibility, flight_number, origin_id, destination_id, distance_km, cabin_class, seat)
  on public.checkins to anon, authenticated;
create policy "read if visible" on public.checkins for select to anon, authenticated
  using (private.can_view_checkin_row(user_id, visibility, occurred_at));

grant select on public.checkin_photos to anon, authenticated;
create policy "read if check-in visible" on public.checkin_photos for select to anon, authenticated
  using (private.can_view_checkin(checkin_id));

grant select on public.sessions to authenticated;
create policy "read own" on public.sessions for select to authenticated
  using (user_id = (select auth.uid()));

-- Spotting locations: new ones wait for moderation. status can't be set by clients.
grant select on public.spotting_locations to anon, authenticated;
grant insert (airport_id, name, location, description, best_time, legal_notes, created_by)
  on public.spotting_locations to authenticated;
create policy "read approved or own" on public.spotting_locations for select to anon, authenticated
  using (status = 'approved' or created_by = (select auth.uid()));
create policy "submit own" on public.spotting_locations for insert to authenticated
  with check (created_by = (select auth.uid()));

-- Badges
grant select on public.user_badges to anon, authenticated;
create policy "read if profile visible" on public.user_badges for select to anon, authenticated
  using (private.can_view_profile_content(user_id));

-- Devices: writes go through register_device, so a user can't claim a token without its checks.
grant select, delete on public.devices to authenticated;
create policy "read own" on public.devices for select to authenticated
  using (user_id = (select auth.uid()));
create policy "delete own" on public.devices for delete to authenticated
  using (user_id = (select auth.uid()));

-- The latest sign-in owns a device. Removing the same token from other rows means a phone that
-- changed accounts stops receiving the previous account's notifications.
create function public.register_device(
  device_id uuid,
  device_platform public.platform,
  device_app_version text,
  device_push_token text default null,
  device_push_env text default null,
  device_os_version text default null,
  device_locale text default null
) returns public.devices
language plpgsql security definer set search_path = '' as $$
declare
  result public.devices;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  if device_push_token is not null then
    delete from public.devices
    where platform = device_platform and push_token = device_push_token and id <> device_id;
  end if;

  insert into public.devices (id, user_id, platform, push_token, push_env, app_version,
                              os_version, locale, last_seen_at)
  values (device_id, auth.uid(), device_platform, device_push_token, device_push_env,
          device_app_version, device_os_version, device_locale, now())
  on conflict (id) do update set
    user_id = excluded.user_id,
    platform = excluded.platform,
    push_token = excluded.push_token,
    push_env = excluded.push_env,
    app_version = excluded.app_version,
    os_version = excluded.os_version,
    locale = excluded.locale,
    last_seen_at = excluded.last_seen_at
  returning * into result;

  return result;
end;
$$;
revoke execute on function public.register_device(uuid, public.platform, text, text, text, text, text)
  from public;
grant execute on function public.register_device(uuid, public.platform, text, text, text, text, text)
  to authenticated;

-- Notification settings
grant select on public.notification_prefs to authenticated;
grant update (salutes, comments, new_followers, friend_badges, wishlist_alerts, airport_geofence)
  on public.notification_prefs to authenticated;
create policy "read own" on public.notification_prefs for select to authenticated
  using (user_id = (select auth.uid()));
create policy "update own" on public.notification_prefs for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- Entitlements: readable by their owner, written only by the service role.
grant select (user_id, entitlement, store, product_id, status, expires_at, auto_renew, updated_at)
  on public.entitlements to authenticated;
create policy "read own" on public.entitlements for select to authenticated
  using (user_id = (select auth.uid()));

-- store_events and reports have RLS on and no grants: service role only.

-- Follows
grant select on public.follows to anon, authenticated;
grant insert (follower, followee), delete on public.follows to authenticated;
create policy "read if both visible or own" on public.follows for select to anon, authenticated
  using (
    follower = (select auth.uid()) or followee = (select auth.uid())
    or (private.can_view_profile_content(follower) and private.can_view_profile_content(followee))
  );
create policy "follow unless blocked" on public.follows for insert to authenticated
  with check (follower = (select auth.uid()) and not private.is_blocked(follower, followee));
create policy "unfollow or remove follower" on public.follows for delete to authenticated
  using (follower = (select auth.uid()) or followee = (select auth.uid()));

-- Salutes and comments follow the check-in they belong to.
grant select on public.salutes to anon, authenticated;
grant insert, delete on public.salutes to authenticated;
create policy "read if visible" on public.salutes for select to anon, authenticated
  using (
    private.can_view_checkin(checkin_id)
    and not coalesce(private.is_blocked((select auth.uid()), user_id), false)
  );
create policy "salute own if visible" on public.salutes for insert to authenticated
  with check (user_id = (select auth.uid()) and private.can_view_checkin(checkin_id));
create policy "remove own" on public.salutes for delete to authenticated
  using (user_id = (select auth.uid()));

grant select on public.comments to anon, authenticated;
grant insert (checkin_id, user_id, body), delete on public.comments to authenticated;
create policy "read if visible" on public.comments for select to anon, authenticated
  using (
    private.can_view_checkin(checkin_id)
    and not coalesce(private.is_blocked((select auth.uid()), user_id), false)
  );
create policy "comment as self if visible" on public.comments for insert to authenticated
  with check (user_id = (select auth.uid()) and private.can_view_checkin(checkin_id));
create policy "delete own or on own check-in" on public.comments for delete to authenticated
  using (
    user_id = (select auth.uid())
    or exists (
      select 1 from public.checkins c
      where c.id = checkin_id and c.user_id = (select auth.uid())
    )
  );

-- Blocks are visible only to the person who created them.
grant select, insert, delete on public.blocks to authenticated;
create policy "read own" on public.blocks for select to authenticated
  using (blocker = (select auth.uid()));
create policy "block as self" on public.blocks for insert to authenticated
  with check (blocker = (select auth.uid()));
create policy "unblock own" on public.blocks for delete to authenticated
  using (blocker = (select auth.uid()));
