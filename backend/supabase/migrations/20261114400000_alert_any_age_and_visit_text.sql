-- Alerts for new check-ins no longer skip check-ins that are more than a day old: a flight added later still
-- tells the people who asked for alerts. The limits stay: 30 a day, no repeats within an hour, and the two airport
-- visits a flight creates are not announced because the flight is.
create or replace function private.notify_checkin() returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_watcher uuid;
begin
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

-- An airport alert also says why the person was there and which airport it is.
drop function public.claim_notifications(integer);
create function public.claim_notifications(batch_size integer default 50)
returns table (
  id uuid, kind text, actor_id uuid, actor_username text, actor_name text, checkin_id uuid,
  subject text, snippet text, devices jsonb, checkin_kind text, visit_context text, airport_name text
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
        'id', dv.id, 'token', dv.push_token, 'env', coalesce(dv.push_env, 'production'), 'locale', dv.locale, 'platform', dv.platform))
      from public.devices dv
      where dv.user_id = m.recipient and dv.platform in ('ios', 'android') and dv.push_token is not null
    ), '[]'::jsonb),
    (select c.kind::text from public.checkins c where c.id = m.checkin_id),
    (select c.visit_context from public.checkins c where c.id = m.checkin_id and c.kind = 'airport'),
    (select ap.name from public.checkins c join public.airports ap on ap.id = c.airport_id
     where c.id = m.checkin_id and c.kind = 'airport')
  from marked m
  join public.profiles p on p.id = m.actor;
end;
$$;

revoke execute on function public.claim_notifications(integer) from public, anon, authenticated;
grant execute on function public.claim_notifications(integer) to service_role;
