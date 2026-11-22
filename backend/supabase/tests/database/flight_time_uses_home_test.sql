-- Flights and their visits take the person's home time for day-based badges, not the faraway airport's time.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

insert into auth.users (id, aud, role, email) values
  ('00000000-0000-0000-0000-0000000000f1', 'authenticated', 'authenticated', 'flighttime1@example.test');
insert into public.airports (id, icao, iata, name, country_code, continent, location) values
  (897001, 'ZZZT', 'ZZT', 'Flight time east', 'JP', 'AS', 'POINT(150 36)'),
  (897002, 'ZZZU', 'ZZU', 'Flight time home', 'DE', 'EU', 'POINT(8 50)');
update public.profiles set home_airport = 897002 where id = '00000000-0000-0000-0000-0000000000f1';

create function pg_temp.value(uid uuid, badge text) returns bigint language sql as $$
  select value from private.badge_values(uid) where badge_id = badge;
$$;

-- A flight logged on Friday 2026-03-06 at 20:00 UTC. At longitude 150 that would be Saturday 06:00, at home it is Friday 21:00.
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000f1', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);
select public.sync_checkins(jsonb_build_array(
  jsonb_build_object('id', 'f0000000-0000-7000-8000-000000000001', 'kind', 'flown', 'occurred_at', '2026-03-06T20:00:00Z', 'origin_id', 897002, 'destination_id', 897001),
  jsonb_build_object('id', 'f0000000-0000-7000-8000-000000000002', 'kind', 'airport', 'occurred_at', '2026-03-06T20:00:00Z', 'airport_id', 897002, 'context', 'departing', 'flight_id', 'f0000000-0000-7000-8000-000000000001'),
  jsonb_build_object('id', 'f0000000-0000-7000-8000-000000000003', 'kind', 'airport', 'occurred_at', '2026-03-06T20:00:00Z', 'airport_id', 897001, 'context', 'arriving', 'flight_id', 'f0000000-0000-7000-8000-000000000001')));
select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);

select is((select count(distinct local_ts::date) from private.checkin_facts('00000000-0000-0000-0000-0000000000f1')), 1::bigint,
          'a flight and its visits fall on one day');
select is((select max(local_ts)::text from private.checkin_facts('00000000-0000-0000-0000-0000000000f1')), '2026-03-06 21:00:00',
          'at the home time of the person');
select is(pg_temp.value('00000000-0000-0000-0000-0000000000f1', 'weekend_warrior'), 0::bigint,
          'a Friday flight is not a weekend');
select is(pg_temp.value('00000000-0000-0000-0000-0000000000f1', 'busy_day'), 3::bigint,
          'and all its rows are on the same day');

-- A standalone airport check-in keeps the time at the airport: Saturday 20:00 UTC at longitude 150 is Sunday 06:00
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000f1', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);
select public.sync_checkins(jsonb_build_array(
  jsonb_build_object('id', 'f0000000-0000-7000-8000-000000000011', 'kind', 'airport', 'occurred_at', '2026-03-07T20:00:00Z', 'airport_id', 897001, 'context', 'spotting')));
select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
select is(pg_temp.value('00000000-0000-0000-0000-0000000000f1', 'weekend_warrior'), 1::bigint,
          'a standalone airport check-in is a weekend at the weekend where it is');

select * from finish();
rollback;
