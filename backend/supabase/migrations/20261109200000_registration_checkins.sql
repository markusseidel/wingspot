-- Milestone 11d: the check-ins of one aircraft, by registration, as far as the caller may see them.
-- Runs as the caller, so the check-in rules decide which rows count. A sensitive aircraft shows only its owner's own
-- check-ins, so for anyone else it gives the same empty answer as a registration nobody has seen. The registration
-- is matched without case, hyphens and spaces (DAIPC finds D-AIPC).
create function public.get_registration_checkins(registration text, before_time timestamptz default null,
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
    a.registration,
    coalesce(c.type_icao, a.type_icao),
    t.manufacturer || ' ' || t.model,
    c.airport_id, coalesce(ap.iata, ap.icao),
    coalesce(o.iata, o.icao), coalesce(d.iata, d.icao),
    c.flight_number, c.distance_km,
    (select count(*)::integer from public.salutes s where s.checkin_id = c.id),
    (select count(*)::integer from public.comments m where m.checkin_id = c.id),
    exists (select 1 from public.salutes s where s.checkin_id = c.id and s.user_id = auth.uid())
  from public.checkins c
  join public.aircraft a on a.id = c.aircraft_id
  join public.profiles p on p.id = c.user_id
  left join public.aircraft_types t on t.icao_code = coalesce(c.type_icao, a.type_icao)
  left join public.airports ap on ap.id = c.airport_id
  left join public.airports o on o.id = c.origin_id
  left join public.airports d on d.id = c.destination_id
  where upper(regexp_replace(a.registration, '[^A-Za-z0-9]', '', 'g')) = upper(regexp_replace(get_registration_checkins.registration, '[^A-Za-z0-9]', '', 'g'))
    and not (a.is_sensitive and c.user_id <> auth.uid())
    and (before_time is null or (c.occurred_at, c.id) < (before_time, before_id))
  order by c.occurred_at desc, c.id desc
  limit least(greatest(coalesce(page_size, 30), 1), 50);
$$;
revoke execute on function public.get_registration_checkins(text, timestamptz, uuid, integer) from public;
grant execute on function public.get_registration_checkins(text, timestamptz, uuid, integer) to authenticated;
