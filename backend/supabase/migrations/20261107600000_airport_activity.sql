-- Milestone 8e: what happens at one airport, as far as the caller may see it.
-- Both functions run as the caller, so the check-in rules decide which rows count (own, friends, public with the
-- author's delay and private profile, and nothing when blocked).

-- The check-ins at an airport (visits and spotted aircraft), newest first, in pages. Same columns as get_feed.
create function public.get_airport_checkins(airport integer, before_time timestamptz default null,
                                            before_id uuid default null, page_size integer default 30)
returns table (
  id uuid, user_id uuid, username text, display_name text, kind public.checkin_kind,
  occurred_at timestamptz, registration text, type_icao text, type_name text,
  airport_id integer, airport_code text, origin_code text, destination_code text,
  flight_number text, distance_km integer, salutes integer, comments integer, saluted boolean
)
language sql stable security invoker set search_path = '' as $$
  select
    c.id, c.user_id, p.username, p.display_name, c.kind, c.occurred_at,
    case when a.is_sensitive and c.user_id <> auth.uid() then null else a.registration end,
    coalesce(c.type_icao, a.type_icao),
    t.manufacturer || ' ' || t.model,
    c.airport_id, coalesce(ap.iata, ap.icao),
    null::text, null::text,
    c.flight_number, c.distance_km,
    (select count(*)::integer from public.salutes s where s.checkin_id = c.id),
    (select count(*)::integer from public.comments m where m.checkin_id = c.id),
    exists (select 1 from public.salutes s where s.checkin_id = c.id and s.user_id = auth.uid())
  from public.checkins c
  join public.profiles p on p.id = c.user_id
  left join public.aircraft a on a.id = c.aircraft_id
  left join public.aircraft_types t on t.icao_code = coalesce(c.type_icao, a.type_icao)
  left join public.airports ap on ap.id = c.airport_id
  where c.airport_id = airport
    and c.kind <> 'flown'
    and (before_time is null or (c.occurred_at, c.id) < (before_time, before_id))
  order by c.occurred_at desc, c.id desc
  limit least(greatest(coalesce(page_size, 30), 1), 50);
$$;
revoke execute on function public.get_airport_checkins(integer, timestamptz, uuid, integer) from public;
grant execute on function public.get_airport_checkins(integer, timestamptz, uuid, integer) to authenticated;

-- A few numbers for the airport page: check-ins in the last 30 days, different aircraft among them, and the most
-- active people. A sensitive aircraft of someone else is not counted, so its visit can't be guessed from the number.
create function public.get_airport_activity(airport integer)
returns table (checkins_30d integer, aircraft_30d integer, top_spotters jsonb)
language sql stable security invoker set search_path = '' as $$
  with recent as (
    select c.id, c.user_id, c.aircraft_id,
           (a.is_sensitive and c.user_id <> auth.uid()) as hidden_aircraft
    from public.checkins c
    left join public.aircraft a on a.id = c.aircraft_id
    where c.airport_id = airport and c.kind <> 'flown' and c.occurred_at > now() - interval '30 days'
  ), spotters as (
    select r.user_id, p.username, p.display_name, count(*)::integer as n
    from recent r join public.profiles p on p.id = r.user_id
    group by r.user_id, p.username, p.display_name
    order by n desc, p.username
    limit 3
  )
  select
    (select count(*)::integer from recent),
    (select count(distinct aircraft_id)::integer from recent where aircraft_id is not null and not hidden_aircraft),
    coalesce((select jsonb_agg(jsonb_build_object('user_id', user_id, 'username', username,
                                                  'display_name', display_name, 'checkins', n) order by n desc, username)
              from spotters), '[]'::jsonb);
$$;
revoke execute on function public.get_airport_activity(integer) from public;
grant execute on function public.get_airport_activity(integer) to authenticated;
