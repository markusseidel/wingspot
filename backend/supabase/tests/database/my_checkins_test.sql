-- Restoring a person's own check-ins: only their own, all fields, paged oldest first.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

insert into auth.users (id, aud, role, email) values
  ('00000000-0000-0000-0000-000000000d01', 'authenticated', 'authenticated', 'mine1@example.test'),
  ('00000000-0000-0000-0000-000000000d02', 'authenticated', 'authenticated', 'mine2@example.test');
insert into public.aircraft_types (icao_code, manufacturer, model) values ('A321', 'Airbus', 'A321');
insert into public.airports (id, icao, iata, name, country_code, continent, location) values
  (990001, 'ZZZA', 'ZZA', 'A', 'DE', 'EU', 'POINT(8 50)'), (990002, 'ZZZB', 'ZZB', 'B', 'DE', 'EU', 'POINT(9 50)');
insert into public.aircraft (id, registration, type_icao) values (990001, 'ZZ-TST', 'A321');
insert into public.checkins (id, user_id, kind, occurred_at, visibility, aircraft_id, airport_id) values
  ('d0000000-0000-7000-8000-00000000000a', '00000000-0000-0000-0000-000000000d01', 'spotted', '2026-01-01T10:00:00Z', 'private', 990001, 990001),
  ('d0000000-0000-7000-8000-00000000000b', '00000000-0000-0000-0000-000000000d02', 'spotted', '2026-01-02T10:00:00Z', 'public', 990001, 990001);
insert into public.checkins (id, user_id, kind, occurred_at, visibility, airport_id, visit_context) values
  ('d0000000-0000-7000-8000-00000000000c', '00000000-0000-0000-0000-000000000d01', 'airport', '2026-02-01T10:00:00Z', 'private', 990002, 'arriving');
insert into public.checkins (id, user_id, kind, occurred_at, visibility, origin_id, destination_id, flight_number, cabin_class, seat) values
  ('d0000000-0000-7000-8000-00000000000d', '00000000-0000-0000-0000-000000000d01', 'flown', '2026-03-01T10:00:00Z', 'private', 990001, 990002, 'LH123', 'economy', '12A');
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000d01', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);

select is((select count(*)::int from public.get_my_checkins()), 3, 'only my own check-ins come back, private ones included');
select is((select string_agg(right(id::text, 1), '' order by ord) from (select id, row_number() over () ord from public.get_my_checkins()) f), 'acd', 'oldest first');
select is((select registration from public.get_my_checkins() where right(id::text, 1) = 'a'), 'ZZ-TST', 'the registration is there');
select is((select type_icao from public.get_my_checkins() where right(id::text, 1) = 'a'), 'A321', 'and the type of the aircraft');
select is((select airport_code from public.get_my_checkins() where right(id::text, 1) = 'a'), 'ZZA', 'and the airport code');
select is((select visit_context from public.get_my_checkins() where right(id::text, 1) = 'c'), 'arriving', 'the reason for a visit');
select is((select origin_code || '>' || destination_code || ' ' || flight_number || ' ' || cabin || ' ' || seat from public.get_my_checkins() where right(id::text, 1) = 'd'),
          'ZZA>ZZB LH123 economy 12A', 'the details of a flight');
select is((select string_agg(right(id::text, 1), '') from public.get_my_checkins('2026-01-01T10:00:00Z', 'd0000000-0000-7000-8000-00000000000a', 1)), 'c', 'the next page, one at a time');
select is((select count(*)::int from public.get_my_checkins('2026-03-01T10:00:00Z', 'd0000000-0000-7000-8000-00000000000d')), 0, 'nothing after the last one');

select * from finish();
rollback;
