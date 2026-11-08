-- Milestone 10b: push notifications. An outbox of what to tell people, filled by triggers, and the functions the
-- send-push Edge function uses to take rows and report back. Nothing here sends anything by itself.

create extension if not exists pg_net;
create extension if not exists pg_cron;

create table public.notifications (
  id          uuid primary key default gen_random_uuid(),
  recipient   uuid not null references public.profiles on delete cascade,
  kind        text not null check (kind in ('follow', 'salute', 'comment')),
  actor       uuid not null references public.profiles on delete cascade,
  checkin_id  uuid references public.checkins on delete cascade,
  snippet     text,
  created_at  timestamptz not null default now(),
  claimed_at  timestamptz,
  attempts    integer not null default 0,
  sent_at     timestamptz
);
create index notifications_pending_idx on public.notifications (created_at) where sent_at is null;
create index notifications_recipient_idx on public.notifications (recipient, created_at);
create index notifications_actor_idx on public.notifications (actor);
create index notifications_checkin_idx on public.notifications (checkin_id);
-- No policies and no grants: only the functions below and the service role touch it.
alter table public.notifications enable row level security;

-- Adds one row if the person should be told: not yourself, not someone you blocked or who blocked you, the kind is
-- switched on, an iPhone is registered, fewer than 30 today, and not the same thing again within the hour.
create function private.queue_notification(to_user uuid, notify_kind text, from_user uuid, for_checkin uuid, text_snippet text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if to_user is null or to_user = from_user then return; end if;
  if private.is_blocked(to_user, from_user) then return; end if;
  if not coalesce((
    select case notify_kind when 'follow' then p.new_followers when 'salute' then p.salutes when 'comment' then p.comments end
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

-- A failing notification must never undo the follow, salute or comment that caused it.
create function private.notify_follow() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform private.queue_notification(new.followee, 'follow', new.follower, null, null);
  return null;
exception when others then
  raise warning 'notify_follow failed: %', sqlerrm;
  return null;
end;
$$;
create trigger follows_notify after insert on public.follows
  for each row execute function private.notify_follow();

create function private.notify_salute() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform private.queue_notification(
    (select c.user_id from public.checkins c where c.id = new.checkin_id), 'salute', new.user_id, new.checkin_id, null);
  return null;
exception when others then
  raise warning 'notify_salute failed: %', sqlerrm;
  return null;
end;
$$;
create trigger salutes_notify after insert on public.salutes
  for each row execute function private.notify_salute();

create function private.notify_comment() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform private.queue_notification(
    (select c.user_id from public.checkins c where c.id = new.checkin_id), 'comment', new.user_id, new.checkin_id,
    left(new.body, 80));
  return null;
exception when others then
  raise warning 'notify_comment failed: %', sqlerrm;
  return null;
end;
$$;
create trigger comments_notify after insert on public.comments
  for each row execute function private.notify_comment();

-- Wakes the send-push function. The address and a shared secret live in the Vault, set by hand after deploying
-- (names push_url and push_secret). Without them nothing is called, so a fresh database and the tests stay quiet.
create function private.call_push() returns void language plpgsql security definer set search_path = '' as $$
declare
  push_url text;
  push_secret text;
begin
  select s.decrypted_secret into push_url from vault.decrypted_secrets s where s.name = 'push_url';
  select s.decrypted_secret into push_secret from vault.decrypted_secrets s where s.name = 'push_secret';
  if push_url is not null and push_secret is not null then
    perform net.http_post(
      url := push_url,
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', push_secret),
      body := '{}'::jsonb,
      timeout_milliseconds := 5000
    );
  end if;
exception when others then
  raise warning 'call_push failed: %', sqlerrm;
end;
$$;

create function private.poke_push() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform private.call_push();
  return null;
end;
$$;
create trigger notifications_poke after insert on public.notifications
  for each statement execute function private.poke_push();

-- Every minute, in case a call was missed or a send failed and is waiting for another try.
select cron.schedule(
  'push-backstop', '* * * * *',
  $$ select private.call_push()
     where exists (select 1 from public.notifications n
                   where n.sent_at is null and n.attempts < 5 and n.created_at > now() - interval '1 day') $$
);

-- For the Edge function (service role only): takes up to batch_size rows nobody else is sending, with what is
-- needed to write and send them. Rows older than a day or tried five times are dropped first.
create function public.claim_notifications(batch_size integer default 50)
returns table (
  id uuid, kind text, actor_id uuid, actor_username text, actor_name text, checkin_id uuid,
  subject text, snippet text, devices jsonb
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
              else coalesce(a.registration, c.type_icao, ap.iata, ap.icao)
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
    ), '[]'::jsonb)
  from marked m
  join public.profiles p on p.id = m.actor;
end;
$$;

-- Reports one row done. delivered = false puts it back for another try. Dead devices (Apple says the token is
-- gone) are removed; the app registers again at its next start.
create function public.finish_notification(notification uuid, delivered boolean, dead_devices uuid[] default '{}')
returns void language plpgsql security definer set search_path = '' as $$
begin
  delete from public.devices where id = any(coalesce(dead_devices, '{}'));
  if delivered then
    update public.notifications set sent_at = now() where id = notification;
  else
    update public.notifications set claimed_at = null where id = notification;
  end if;
end;
$$;

revoke execute on function public.claim_notifications(integer) from public, anon, authenticated;
grant execute on function public.claim_notifications(integer) to service_role;
revoke execute on function public.finish_notification(uuid, boolean, uuid[]) from public, anon, authenticated;
grant execute on function public.finish_notification(uuid, boolean, uuid[]) to service_role;
