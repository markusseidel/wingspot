-- A person's own check-ins, oldest first, a page at a time. The apps use it to put them back on a phone that has none
-- of them (a new phone, a reinstall), so the profile numbers, collections and map work there too.
-- Unlike the feed, nothing is hidden: these are the caller's own rows, including sensitive aircraft, private check-ins and
-- the position. It runs as the owner of the function because clients can't read the location and visit_context columns
-- directly; the filter on auth.uid() keeps it to the caller's rows.
create function public.get_my_checkins(after_time timestamptz default null, after_id uuid default null, page_size integer default 200)
returns table (
  id uuid, kind public.checkin_kind, occurred_at timestamptz, registration text, type_icao text,
  airport_id integer, airport_code text, origin_id integer, destination_id integer,
  origin_code text, destination_code text, flight_number text, cabin text, seat text,
  visit_context text, latitude double precision, longitude double precision
)
language sql stable security definer set search_path = '' as $$
  select
    c.id, c.kind, c.occurred_at, a.registration, coalesce(c.type_icao, a.type_icao),
    c.airport_id, coalesce(ap.iata, ap.icao), c.origin_id, c.destination_id,
    coalesce(o.iata, o.icao), coalesce(d.iata, d.icao),
    c.flight_number, c.cabin_class, c.seat, c.visit_context,
    extensions.st_y(c.location::extensions.geometry), extensions.st_x(c.location::extensions.geometry)
  from public.checkins c
  left join public.aircraft a on a.id = c.aircraft_id
  left join public.airports ap on ap.id = c.airport_id
  left join public.airports o on o.id = c.origin_id
  left join public.airports d on d.id = c.destination_id
  where c.user_id = auth.uid()
    and (after_time is null or (c.occurred_at, c.id) > (after_time, after_id))
  order by c.occurred_at, c.id
  limit least(greatest(coalesce(page_size, 200), 1), 500);
$$;
revoke execute on function public.get_my_checkins(timestamptz, uuid, integer) from public;
grant execute on function public.get_my_checkins(timestamptz, uuid, integer) to authenticated;
