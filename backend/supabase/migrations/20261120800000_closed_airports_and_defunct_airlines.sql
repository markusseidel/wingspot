-- Airports that have closed and airlines that no longer fly, so check-ins and flights from the past still have
-- something to point at. Both get a date: `closed_on` for an airport and `ceased_on` for an airline.
-- Airports that are closed stay out of the airport list the apps download, so the ones added here are curated by hand
-- (backend/refdata-pipeline/seed/closed_airports.csv) and given IDs from 9,000,000 up, clear of the OurAirports IDs.
alter table public.airports add column closed_on date;
alter table public.operators add column ceased_on date;

insert into public.airports (id, icao, iata, name, city, country_code, continent, elevation_ft, location, closed_on) values
  (9000001, 'EDDT', 'TXL', 'Berlin Tegel Airport', 'Berlin', 'DE', 'EU', 122, st_geogfromtext('POINT(13.2877 52.5597)'), '2020-11-08'),
  (9000002, 'EDDI', 'THF', 'Berlin Tempelhof Airport', 'Berlin', 'DE', 'EU', 167, st_geogfromtext('POINT(13.4039 52.4725)'), '2008-10-30')
on conflict (id) do update set closed_on = excluded.closed_on;

insert into public.operators (icao, iata, name, country_code, ceased_on) values
  ('BER', 'AB', 'Air Berlin', 'DE', '2017-10-27'),
  ('NLY', 'HG', 'Niki', 'AT', '2017-12-13'),
  ('MON', 'ZB', 'Monarch Airlines', 'GB', '2017-10-02'),
  ('MAH', 'MA', 'Malév Hungarian Airlines', 'HU', '2012-02-03'),
  ('SAB', 'SN', 'Sabena', 'BE', '2001-11-07'),
  ('PAA', 'PA', 'Pan American World Airways', 'US', '1991-12-04'),
  ('TWA', 'TW', 'Trans World Airlines', 'US', '2001-12-01')
on conflict (icao) do update set ceased_on = excluded.ceased_on;

-- Two more metrics for the badge rules. Patched in place so the long function isn't copied again.
--   airports_closed: how many airports that have closed the person has been to (flown from or to, or checked in at).
--   operators_ceased: how many airlines that no longer exist they flew with. A flight belongs to an airline when its
--   flight number starts with the airline's IATA or ICAO code followed by digits, and the flight was not after the
--   airline stopped, so a code that was handed on to another airline later doesn't count for the old one.
do $$
declare
  def text := pg_get_functiondef('private.badge_values(uuid)'::regprocedure);
  marker text := 'when ''checkins_total'' then';
begin
  if position(marker in def) = 0 then
    raise exception 'badge_values has no checkins_total metric to anchor on';
  end if;
  execute replace(def, marker,
    'when ''airports_closed'' then (select count(*) from public.airports ap where ap.closed_on is not null '
    || 'and exists (select 1 from public.checkins c where c.user_id = uid and ap.id in (c.airport_id, c.origin_id, c.destination_id))) '
    || 'when ''operators_ceased'' then (select count(distinct o.id) from public.operators o '
    || 'join public.checkins c on c.user_id = uid and c.kind = ''flown'' and c.flight_number is not null '
    || 'where o.ceased_on is not null and c.occurred_at::date <= o.ceased_on '
    || 'and (upper(regexp_replace(c.flight_number, ''\s'', '''', ''g'')) ~ (''^'' || coalesce(o.iata, ''-'') || ''[0-9]'') '
    || 'or upper(regexp_replace(c.flight_number, ''\s'', '''', ''g'')) ~ (''^'' || coalesce(o.icao, ''-'') || ''[0-9]''))) '
    || marker);
end;
$$;
