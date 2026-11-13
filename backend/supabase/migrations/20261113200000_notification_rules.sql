-- Milestone 12c: alerts for the check-ins of people you follow. You choose, per person, whether a new spotted,
-- flown or airport check-in sends you a push. Nothing here tells the other person.

create table public.notification_rules (
  watcher    uuid not null references public.profiles on delete cascade,
  target     uuid not null references public.profiles on delete cascade,
  spotted    boolean not null default false,
  flown      boolean not null default false,
  airport    boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (watcher, target),
  check (watcher <> target)
);
create index notification_rules_target_idx on public.notification_rules (target);
alter table public.notification_rules enable row level security;
grant select, insert, update, delete on public.notification_rules to authenticated;
create policy "read own" on public.notification_rules for select to authenticated
  using (watcher = (select auth.uid()));
-- Only for people you follow.
create policy "add own" on public.notification_rules for insert to authenticated
  with check (watcher = (select auth.uid())
              and exists (select 1 from public.follows f where f.follower = watcher and f.followee = target));
create policy "change own" on public.notification_rules for update to authenticated
  using (watcher = (select auth.uid())) with check (watcher = (select auth.uid()));
create policy "delete own" on public.notification_rules for delete to authenticated
  using (watcher = (select auth.uid()));

-- Unfollowing ends the alerts.
create function private.end_rules_on_unfollow() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  delete from public.notification_rules r where r.watcher = old.follower and r.target = old.followee;
  return null;
end;
$$;
create trigger follows_end_rules after delete on public.follows
  for each row execute function private.end_rules_on_unfollow();

-- One switch to turn all of these alerts off at once.
alter table public.notification_prefs add column followed_checkins boolean not null default true;

alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check
  check (kind in ('follow', 'salute', 'comment', 'checkin'));

-- Like private.can_view_checkin_row, for a given viewer instead of the caller. A public check-in of someone with a
-- posting delay is not visible until the delay has passed, so it sends no alert.
create function private.can_view_checkin_row_as(viewer uuid, author uuid, row_visibility text, occurred timestamptz)
returns boolean
language sql stable security definer set search_path = '' as $$
  select case
    when viewer = author then true
    when coalesce(private.is_blocked(viewer, author), false) then false
    when row_visibility = 'friends' then coalesce(private.are_friends(viewer, author), false)
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

create or replace function private.queue_notification(to_user uuid, notify_kind text, from_user uuid, for_checkin uuid, text_snippet text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if to_user is null or to_user = from_user then return; end if;
  if private.is_blocked(to_user, from_user) then return; end if;
  if not coalesce((
    select case notify_kind when 'follow' then p.new_followers when 'salute' then p.salutes when 'comment' then p.comments
                     when 'checkin' then p.followed_checkins end
    from public.notification_prefs p where p.user_id = to_user
  ), true) then return; end if;
  if not exists (
    select 1 from public.devices d where d.user_id = to_user and d.platform = 'ios' and d.push_token is not null
  ) then return; end if;
  if (select count(*) from public.notifications n
      where n.recipient = to_user and n.created_at > now() - interval '24 hours') >= 30 then return; end if;
  if notify_kind <> 'comment' and exists (
    select 1 from public.notifications n
    where n.recipient = to_user and n.kind = notify_kind and n.actor = from_user
      and n.checkin_id is not distinct from for_checkin and n.created_at > now() - interval '1 hour'
  ) then return; end if;
  insert into public.notifications (recipient, kind, actor, checkin_id, snippet)
  values (to_user, notify_kind, from_user, for_checkin, text_snippet);
end;
$$;


-- A new check-in tells the people who set an alert for it. Not for old ones that were added later (a flight from
-- last year), not for edits (this runs on insert only), and not for the airport visits a flight creates, because
-- the flight is announced.
create function private.notify_checkin() returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_watcher uuid;
begin
  if new.occurred_at < now() - interval '1 day' then return null; end if;
  if new.kind = 'airport' and new.visit_context in ('departing', 'arriving') then return null; end if;
  for v_watcher in
    select r.watcher from public.notification_rules r
    where r.target = new.user_id
      and case new.kind when 'spotted' then r.spotted when 'flown' then r.flown when 'airport' then r.airport end
      and exists (select 1 from public.follows f where f.follower = r.watcher and f.followee = new.user_id)
  loop
    if private.can_view_checkin_row_as(v_watcher, new.user_id, new.visibility, new.occurred_at) then
      perform private.queue_notification(v_watcher, 'checkin', new.user_id, new.id, null);
    end if;
  end loop;
  return null;
exception when others then
  raise warning 'notify_checkin failed: %', sqlerrm;
  return null;
end;
$$;
create trigger checkins_notify after insert on public.checkins
  for each row execute function private.notify_checkin();

-- The alert text depends on the kind of check-in, and a sensitive aircraft's registration is never sent to others.
drop function public.claim_notifications(integer);
create function public.claim_notifications(batch_size integer default 50)
returns table (
  id uuid, kind text, actor_id uuid, actor_username text, actor_name text, checkin_id uuid,
  subject text, snippet text, devices jsonb, checkin_kind text
)
language plpgsql security definer set search_path = '' as $$
begin
  update public.notifications n set sent_at = now()
  where n.sent_at is null and (n.created_at < now() - interval '1 day' or n.attempts >= 5);

  return query
  with picked as (
    select n.id from public.notifications n
    where n.sent_at is null and (n.claimed_at is null or n.claimed_at < now() - interval '5 minutes')
    order by n.created_at
    limit greatest(least(coalesce(batch_size, 50), 100), 1)
    for update skip locked
  ), marked as (
    update public.notifications n set claimed_at = now(), attempts = n.attempts + 1
    from picked where n.id = picked.id
    returning n.id, n.recipient, n.kind, n.actor, n.checkin_id, n.snippet
  )
  select
    m.id, m.kind, m.actor, p.username, p.display_name, m.checkin_id,
    (select case
              when c.kind = 'flown' then coalesce(o.iata, o.icao) || ' → ' || coalesce(d.iata, d.icao)
              when c.kind = 'airport' then coalesce(ap.iata, ap.icao)
              else coalesce(case when a.is_sensitive and c.user_id <> m.recipient then null else a.registration end,
                            c.type_icao, a.type_icao, ap.iata, ap.icao)
            end
     from public.checkins c
     left join public.aircraft a on a.id = c.aircraft_id
     left join public.airports ap on ap.id = c.airport_id
     left join public.airports o on o.id = c.origin_id
     left join public.airports d on d.id = c.destination_id
     where c.id = m.checkin_id),
    m.snippet,
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', dv.id, 'token', dv.push_token, 'env', coalesce(dv.push_env, 'production'), 'locale', dv.locale))
      from public.devices dv
      where dv.user_id = m.recipient and dv.platform = 'ios' and dv.push_token is not null
    ), '[]'::jsonb),
    (select c.kind::text from public.checkins c where c.id = m.checkin_id)
  from marked m
  join public.profiles p on p.id = m.actor;
end;
$$;


revoke execute on function public.claim_notifications(integer) from public, anon, authenticated;
grant execute on function public.claim_notifications(integer) to service_role;

-- The export lists your alerts too.
create or replace function public.export_my_data()
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  result jsonb;
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select jsonb_build_object(
    'exported_at', now(),
    'profile', (select to_jsonb(p) from public.profiles p where p.id = uid),
    'notification_prefs', (select to_jsonb(n) - 'user_id' from public.notification_prefs n where n.user_id = uid),
    'checkins', coalesce((
      select jsonb_agg(
        (to_jsonb(c) - 'user_id' - 'location')
        || jsonb_build_object(
             'registration', a.registration,
             'airport_code', coalesce(ap.iata, ap.icao),
             'origin_code', coalesce(o.iata, o.icao),
             'destination_code', coalesce(d.iata, d.icao),
             'latitude', extensions.st_y(c.location::extensions.geometry),
             'longitude', extensions.st_x(c.location::extensions.geometry))
        order by c.occurred_at, c.id)
      from public.checkins c
      left join public.aircraft a on a.id = c.aircraft_id
      left join public.airports ap on ap.id = c.airport_id
      left join public.airports o on o.id = c.origin_id
      left join public.airports d on d.id = c.destination_id
      where c.user_id = uid
    ), '[]'::jsonb),
    'alert_rules', coalesce((
      select jsonb_agg(jsonb_build_object('username', p.username, 'spotted', r.spotted, 'flown', r.flown,
                                          'airport', r.airport) order by p.username)
      from public.notification_rules r join public.profiles p on p.id = r.target where r.watcher = uid
    ), '[]'::jsonb),
    'photos', coalesce((
      select jsonb_agg(jsonb_build_object('id', ph.id, 'checkin_id', ph.checkin_id, 'width', ph.width,
                                          'height', ph.height, 'position', ph.position) order by ph.checkin_id, ph.position)
      from public.checkin_photos ph join public.checkins c on c.id = ph.checkin_id
      where c.user_id = uid
    ), '[]'::jsonb),
    'comments_written', coalesce((
      select jsonb_agg(to_jsonb(m) - 'user_id' order by m.created_at, m.id)
      from public.comments m where m.user_id = uid
    ), '[]'::jsonb),
    'salutes_given', coalesce((
      select jsonb_agg(jsonb_build_object('checkin_id', s.checkin_id) order by s.checkin_id)
      from public.salutes s where s.user_id = uid
    ), '[]'::jsonb),
    'following', coalesce((
      select jsonb_agg(jsonb_build_object('username', p.username, 'since', f.created_at) order by f.created_at)
      from public.follows f join public.profiles p on p.id = f.followee where f.follower = uid
    ), '[]'::jsonb),
    'followers', coalesce((
      select jsonb_agg(jsonb_build_object('username', p.username, 'since', f.created_at) order by f.created_at)
      from public.follows f join public.profiles p on p.id = f.follower where f.followee = uid
    ), '[]'::jsonb),
    'blocked', coalesce((
      select jsonb_agg(jsonb_build_object('username', p.username) order by p.username)
      from public.blocks b join public.profiles p on p.id = b.blocked where b.blocker = uid
    ), '[]'::jsonb),
    'badges', coalesce((
      select jsonb_agg(to_jsonb(ub) - 'user_id' order by ub.badge_id)
      from public.user_badges ub where ub.user_id = uid
    ), '[]'::jsonb),
    'reports_filed', coalesce((
      select jsonb_agg(jsonb_build_object('target_type', r.target_type, 'target_id', r.target_id,
                                          'reason', r.reason, 'status', r.status, 'created_at', r.created_at)
                       order by r.created_at)
      from public.reports r where r.reporter = uid
    ), '[]'::jsonb),
    'devices', coalesce((
      select jsonb_agg(jsonb_build_object('platform', dv.platform, 'app_version', dv.app_version,
                                          'os_version', dv.os_version, 'locale', dv.locale,
                                          'last_seen_at', dv.last_seen_at) order by dv.last_seen_at)
      from public.devices dv where dv.user_id = uid
    ), '[]'::jsonb),
    'entitlements', coalesce((
      select jsonb_agg(jsonb_build_object('entitlement', e.entitlement, 'store', e.store, 'product_id', e.product_id,
                                          'status', e.status, 'expires_at', e.expires_at) order by e.entitlement)
      from public.entitlements e where e.user_id = uid
    ), '[]'::jsonb)
  ) into result;
  return result;
end;
$$;
