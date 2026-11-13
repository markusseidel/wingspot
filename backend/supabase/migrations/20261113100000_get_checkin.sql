-- Milestone 12b: one check-in by id, for the check-in page and for a tap on a notification.
-- Same columns and rules as get_person_checkins, plus the airport ids of a flight. Cabin and seat are returned for
-- your own check-ins only. It runs as the caller, so the check-in rules decide whether a row comes back
-- (own, friends, public with the author's delay and private profile, and nothing when blocked). A check-in the
-- caller may not see gives the same empty answer as one that doesn't exist.
create function public.get_checkin(target uuid)
returns table (
  id uuid, user_id uuid, username text, display_name text, kind public.checkin_kind,
  occurred_at timestamptz, registration text, type_icao text, type_name text,
  airport_id integer, airport_code text, origin_id integer, destination_id integer,
  origin_code text, destination_code text, flight_number text, distance_km integer,
  cabin text, seat text, salutes integer, comments integer, saluted boolean
)
language sql stable security invoker set search_path = '' as $$
  select
    c.id, c.user_id, p.username, p.display_name, c.kind, c.occurred_at,
    case when a.is_sensitive and c.user_id <> auth.uid() then null else a.registration end,
    coalesce(c.type_icao, a.type_icao),
    t.manufacturer || ' ' || t.model,
    c.airport_id, coalesce(ap.iata, ap.icao), c.origin_id, c.destination_id,
    coalesce(o.iata, o.icao), coalesce(d.iata, d.icao),
    c.flight_number, c.distance_km,
    case when c.user_id = auth.uid() then c.cabin_class end,
    case when c.user_id = auth.uid() then c.seat end,
    (select count(*)::integer from public.salutes s where s.checkin_id = c.id),
    (select count(*)::integer from public.comments m where m.checkin_id = c.id),
    exists (select 1 from public.salutes s where s.checkin_id = c.id and s.user_id = auth.uid())
  from public.checkins c
  join public.profiles p on p.id = c.user_id
  left join public.aircraft a on a.id = c.aircraft_id
  left join public.aircraft_types t on t.icao_code = coalesce(c.type_icao, a.type_icao)
  left join public.airports ap on ap.id = c.airport_id
  left join public.airports o on o.id = c.origin_id
  left join public.airports d on d.id = c.destination_id
  where c.id = target;
$$;
revoke execute on function public.get_checkin(uuid) from public;
grant execute on function public.get_checkin(uuid) to authenticated;
