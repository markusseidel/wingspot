-- Companion Sync (#273, docs/COMPANION-SYNC-PLAN.md): take over a friend's flight.
--
-- A request is a tag that was not answered: you are tagged on a flight or an airport visit, you have not left it, and you have no
-- check-in of your own that points at it (source_checkin_id). Accepting is making that copy (the apps do it, as today, so it works
-- offline); declining is the existing remove_my_tag. What was missing, and what this adds:
--   * get_companion_requests: the open requests, on every device.
--   * find_matching_flight: the flights you already have that are the same flight as the one you were tagged on.
--   * link_companion: "keep mine": links a check-in you already have to the source (the link could only be set on first upload).
--   * replace_flight_data: "replace": takes the flight facts of the source over into your own flight, and links it.
--   * get_checkin_source: on a copy, the person whose check-in it was taken from.

-- 1. The rule for "the same flight": the same flight number within 18 hours, or the same route (same two airports, same way round)
--    within 12 hours. Flights are stored with a day (midday), not a clock time, so a window of a few hours would miss the same day
--    entered at different moments. A flight with no number matches on the route only.
create function private.flight_match(p_user uuid, p_number text, p_origin integer, p_destination integer, p_at timestamptz)
returns table (id uuid, reason text, delta interval)
language sql stable security definer set search_path = '' as $$
  select c.id,
         case when n.number <> '' and upper(replace(coalesce(c.flight_number, ''), ' ', '')) = n.number
                   and abs(extract(epoch from (c.occurred_at - p_at))) <= 18 * 3600 then 'number' else 'route' end,
         c.occurred_at - p_at
  from public.checkins c
  cross join (select upper(replace(coalesce(p_number, ''), ' ', '')) as number) n
  where c.user_id = p_user and c.kind = 'flown'
    and ((n.number <> '' and upper(replace(coalesce(c.flight_number, ''), ' ', '')) = n.number
          and abs(extract(epoch from (c.occurred_at - p_at))) <= 18 * 3600)
         or (c.origin_id = p_origin and c.destination_id = p_destination
             and abs(extract(epoch from (c.occurred_at - p_at))) <= 12 * 3600));
$$;
revoke execute on function private.flight_match(uuid, text, integer, integer, timestamptz) from public, anon, authenticated;

-- 2. The open requests of the caller, newest first.
create function public.get_companion_requests()
returns table (
  checkin_id uuid, author_id uuid, username text, display_name text, kind public.checkin_kind, occurred_at timestamptz,
  flight_number text, origin_id integer, destination_id integer, origin_code text, destination_code text,
  airport_id integer, airport_code text, distance_km integer, requested_at timestamptz
)
language sql stable security definer set search_path = '' as $$
  select c.id, c.user_id, p.username, p.display_name, c.kind, c.occurred_at,
         c.flight_number, c.origin_id, c.destination_id, o.iata, d.iata, c.airport_id, a.iata, c.distance_km, t.created_at
  from public.checkin_tags t
  join public.checkins c on c.id = t.checkin_id
  join public.profiles p on p.id = c.user_id
  left join public.airports o on o.id = c.origin_id
  left join public.airports d on d.id = c.destination_id
  left join public.airports a on a.id = c.airport_id
  where auth.uid() is not null and t.user_id = auth.uid()
    and c.kind in ('flown', 'airport')
    and not private.is_flight_visit(c.id)
    and private.can_view_checkin(c.id)
    and not exists (select 1 from public.checkins mine where mine.user_id = auth.uid() and mine.source_checkin_id = c.id)
  order by t.created_at desc, c.id
  limit 50;
$$;
revoke execute on function public.get_companion_requests() from public, anon;
grant execute on function public.get_companion_requests() to authenticated;

-- 3. The caller's flights that are the same flight as the one they were tagged on, best first, at most 3. A flight that already points
--    at another source is somebody else's companion link and is left out.
create function public.find_matching_flight(p_source uuid)
returns table (id uuid, reason text, seconds_apart integer, flight_number text, occurred_at timestamptz,
               origin_id integer, destination_id integer, origin_code text, destination_code text)
language sql stable security definer set search_path = '' as $$
  select c.id, m.reason, round(extract(epoch from m.delta))::integer, c.flight_number, c.occurred_at,
         c.origin_id, c.destination_id, o.iata, d.iata
  from public.checkins s
  join public.checkin_tags t on t.checkin_id = s.id and t.user_id = auth.uid()
  cross join lateral private.flight_match(auth.uid(), s.flight_number, s.origin_id, s.destination_id, s.occurred_at) m
  join public.checkins c on c.id = m.id
  left join public.airports o on o.id = c.origin_id
  left join public.airports d on d.id = c.destination_id
  where auth.uid() is not null and s.id = p_source and s.kind = 'flown'
    and private.can_view_checkin(s.id)
    and (c.source_checkin_id is null or c.source_checkin_id = s.id)
  order by (c.origin_id = s.origin_id and c.destination_id = s.destination_id) desc, (m.reason = 'number') desc, abs(extract(epoch from m.delta)), c.id
  limit 3;
$$;
revoke execute on function public.find_matching_flight(uuid) from public, anon;
grant execute on function public.find_matching_flight(uuid) to authenticated;

-- 4. "Keep mine": link a check-in the caller already has to the check-in they were tagged on. Only when the caller is tagged on the
--    source, the two are the same kind, the caller's check-in has no other source, and no other check-in of the caller points at the
--    source. False when any of that is not so.
create function public.link_companion(p_mine uuid, p_source uuid) returns boolean
language plpgsql volatile security definer set search_path = '' as $$
declare
  mine public.checkins;
  source public.checkins;
begin
  if auth.uid() is null then return false; end if;
  select * into mine from public.checkins where id = p_mine and user_id = auth.uid();
  select * into source from public.checkins where id = p_source;
  if mine.id is null or source.id is null or mine.id = source.id or mine.kind <> source.kind then return false; end if;
  if not exists (select 1 from public.checkin_tags t where t.checkin_id = source.id and t.user_id = auth.uid())
     or not private.can_view_checkin(source.id) then return false; end if;
  if mine.source_checkin_id is not null and mine.source_checkin_id <> source.id then return false; end if;
  if exists (select 1 from public.checkins o where o.user_id = auth.uid() and o.source_checkin_id = source.id and o.id <> mine.id) then return false; end if;
  update public.checkins set source_checkin_id = source.id where id = mine.id;
  return true;
end;
$$;
revoke execute on function public.link_companion(uuid, uuid) from public, anon;
grant execute on function public.link_companion(uuid, uuid) to authenticated;

-- 5. "Replace the flight data": the caller's own flight takes over the facts of the flight they were tagged on: flight number, route,
--    time, aircraft, distance. Their id, photos, notes, seat, cabin, comments, salutes and visibility stay. The two airport visits
--    of the flight follow (their airports, and, through the existing trigger, their time). The flight is linked to the source.
--    Returns the new facts so the app can update its own copy, or null when it is refused (not your flight, not a flight, not tagged,
--    already linked elsewhere, the source is already taken over by another of your check-ins).
create function public.replace_flight_data(p_mine uuid, p_source uuid) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  mine public.checkins;
  source public.checkins;
  v_distance integer;
  v_registration text;
begin
  if auth.uid() is null then return null; end if;
  select * into mine from public.checkins where id = p_mine and user_id = auth.uid() and kind = 'flown';
  select * into source from public.checkins where id = p_source and kind = 'flown';
  if mine.id is null or source.id is null or mine.id = source.id then return null; end if;
  if not exists (select 1 from public.checkin_tags t where t.checkin_id = source.id and t.user_id = auth.uid())
     or not private.can_view_checkin(source.id) then return null; end if;
  if mine.source_checkin_id is not null and mine.source_checkin_id <> source.id then return null; end if;
  if exists (select 1 from public.checkins o where o.user_id = auth.uid() and o.source_checkin_id = source.id and o.id <> mine.id) then return null; end if;

  select round(extensions.st_distance(o.location, d.location) / 1000)::integer into v_distance
  from public.airports o, public.airports d where o.id = source.origin_id and d.id = source.destination_id;

  -- The visits first, while they are still found by their link; the flight's own update then moves their time.
  update public.checkins v set airport_id = case v.visit_context when 'departing' then source.origin_id else source.destination_id end
  where v.user_id = auth.uid() and v.kind = 'airport' and v.flight_id = mine.id and v.visit_context in ('departing', 'arriving');
  update public.checkins set
    flight_number = source.flight_number, origin_id = source.origin_id, destination_id = source.destination_id,
    occurred_at = source.occurred_at, aircraft_id = source.aircraft_id, type_icao = source.type_icao,
    distance_km = v_distance, source_checkin_id = source.id
  where id = mine.id;
  select ac.registration into v_registration from public.aircraft ac where ac.id = source.aircraft_id;
  return jsonb_build_object(
    'flight_number', source.flight_number, 'origin_id', source.origin_id, 'destination_id', source.destination_id,
    'occurred_at', source.occurred_at, 'registration', v_registration, 'type_icao', source.type_icao, 'distance_km', v_distance);
end;
$$;
revoke execute on function public.replace_flight_data(uuid, uuid) from public, anon;
grant execute on function public.replace_flight_data(uuid, uuid) to authenticated;

-- 6. On a copy: the person whose check-in it was taken from, so the copy can say "with Jan". Only for the owner of the copy, and only
--    while they may still see the source.
create function public.get_checkin_source(p_checkin uuid)
returns table (user_id uuid, username text, display_name text)
language sql stable security definer set search_path = '' as $$
  select s.user_id, p.username, p.display_name
  from public.checkins c
  join public.checkins s on s.id = c.source_checkin_id
  join public.profiles p on p.id = s.user_id
  where auth.uid() is not null and c.id = p_checkin and c.user_id = auth.uid()
    and private.can_view_checkin(s.id)
    and not private.is_blocked(auth.uid(), s.user_id);
$$;
revoke execute on function public.get_checkin_source(uuid) from public, anon;
grant execute on function public.get_checkin_source(uuid) to authenticated;
