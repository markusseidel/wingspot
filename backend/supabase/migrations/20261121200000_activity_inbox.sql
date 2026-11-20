-- Activity inbox (docs/SOCIAL-PLAN.md, feature 7). The notifications table was only a push outbox, so people without a
-- phone, or with a kind switched off, got no row. Now every event that concerns a person is stored, and a row the person
-- should not be pushed (no phone, kind switched off, 30 a day reached) is marked `silent` and counts as already sent.
-- The inbox lists them, newest first, and `read_at` says what the person has seen.

alter table public.notifications add column read_at timestamptz;
alter table public.notifications add column silent boolean not null default false;
create index notifications_unread_idx on public.notifications (recipient) where read_at is null;

-- Every kind the next social features need is added now, so they do not touch this constraint again.
alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check
  check (kind in ('follow', 'salute', 'comment', 'checkin', 'tagged', 'mention', 'reply', 'comment_like', 'tag_copy', 'friend_badge'));

-- Stores the event unless it is about yourself, between people who blocked each other, or the same thing again within
-- the hour. Whether it is also pushed is decided here: the kind must be switched on, a phone registered, and fewer
-- than 30 pushes in the last 24 hours. Otherwise the row is silent.
create or replace function private.queue_notification(to_user uuid, notify_kind text, from_user uuid, for_checkin uuid, text_snippet text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_push boolean;
begin
  if to_user is null or to_user = from_user then return; end if;
  if private.is_blocked(to_user, from_user) then return; end if;
  if notify_kind <> 'comment' and exists (
    select 1 from public.notifications n
    where n.recipient = to_user and n.kind = notify_kind and n.actor = from_user
      and n.checkin_id is not distinct from for_checkin and n.created_at > now() - interval '1 hour'
  ) then return; end if;

  v_push := coalesce((
    select case notify_kind when 'follow' then p.new_followers when 'salute' then p.salutes when 'comment' then p.comments
                     when 'checkin' then p.followed_checkins when 'tagged' then p.tagged end
    from public.notification_prefs p where p.user_id = to_user
  ), true);
  if v_push then
    v_push := exists (
      select 1 from public.devices d where d.user_id = to_user and d.platform in ('ios', 'android') and d.push_token is not null
    );
  end if;
  if v_push then
    v_push := (select count(*) from public.notifications n
               where n.recipient = to_user and not n.silent and n.created_at > now() - interval '24 hours') < 30;
  end if;

  insert into public.notifications (recipient, kind, actor, checkin_id, snippet, silent, sent_at)
  values (to_user, notify_kind, from_user, for_checkin, text_snippet, not v_push, case when v_push then null else now() end);
end;
$$;

-- Does this row still belong in the person's inbox? Not if its person is blocked now, or the check-in is no longer
-- something they may see.
create function private.inbox_shows(n public.notifications, viewer uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select n.recipient = viewer
    and not coalesce(private.is_blocked(viewer, n.actor), false)
    and (n.checkin_id is null or private.can_view_checkin(n.checkin_id));
$$;
revoke execute on function private.inbox_shows(public.notifications, uuid) from public, anon, authenticated;

-- The caller's inbox, newest first. `before` is the created_at of the last row of the previous page.
create function public.get_notifications(before timestamptz default null, lim integer default 30)
returns table (
  id uuid, kind text, actor_id uuid, username text, display_name text, checkin_id uuid, subject text, snippet text,
  created_at timestamptz, is_read boolean
)
language sql stable security definer set search_path = '' as $$
  select n.id, n.kind, n.actor, p.username, p.display_name, n.checkin_id,
    (select case
              when c.kind = 'flown' then coalesce(o.iata, o.icao) || ' → ' || coalesce(d.iata, d.icao)
              when c.kind = 'airport' then coalesce(ap.iata, ap.icao)
              else coalesce(a.registration, c.type_icao, ap.iata, ap.icao)
            end
     from public.checkins c
     left join public.aircraft a on a.id = c.aircraft_id
     left join public.airports ap on ap.id = c.airport_id
     left join public.airports o on o.id = c.origin_id
     left join public.airports d on d.id = c.destination_id
     where c.id = n.checkin_id),
    n.snippet, n.created_at, n.read_at is not null
  from public.notifications n
  join public.profiles p on p.id = n.actor
  where auth.uid() is not null
    and n.recipient = auth.uid()
    and (before is null or n.created_at < before)
    and private.inbox_shows(n, auth.uid())
  order by n.created_at desc, n.id desc
  limit greatest(least(coalesce(lim, 30), 100), 1);
$$;

-- How many are unread, for the dot on the bell. Stops counting at 99.
create function public.unread_notification_count() returns integer
language sql stable security definer set search_path = '' as $$
  select count(*)::integer from (
    select 1 from public.notifications n
    where auth.uid() is not null and n.recipient = auth.uid() and n.read_at is null
      and private.inbox_shows(n, auth.uid())
    limit 99
  ) unread;
$$;

-- Marks everything the caller has in the inbox as read.
create function public.mark_notifications_read() returns void
language sql security definer set search_path = '' as $$
  update public.notifications n set read_at = now()
  where auth.uid() is not null and n.recipient = auth.uid() and n.read_at is null;
$$;

revoke execute on function public.get_notifications(timestamptz, integer) from public, anon;
revoke execute on function public.unread_notification_count() from public, anon;
revoke execute on function public.mark_notifications_read() from public, anon;
grant execute on function public.get_notifications(timestamptz, integer) to authenticated;
grant execute on function public.unread_notification_count() to authenticated;
grant execute on function public.mark_notifications_read() to authenticated;

-- The inbox keeps 90 days.
select cron.schedule('notifications-retention', '17 3 * * *',
  $$ delete from public.notifications where created_at < now() - interval '90 days' $$);
