-- Backdated check-ins (#312): a sighting or an airport check-in keeps an old date, the date can be corrected, a date-only entry says so,
-- the sightings of a moved visit follow it, a visit of a flight stays with the flight, and badges follow the event date.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

insert into auth.users (id, aud, role, email) values
  ('00000000-0000-0000-0000-000000000c01', 'authenticated', 'authenticated', 'backdate1@example.test');
insert into public.airports (id, icao, iata, name, country_code, continent, location) values
  (899001, 'ZZBA', 'ZBA', 'Backdate A', 'DE', 'EU', 'POINT(8 50)'),
  (899002, 'ZZBB', 'ZBB', 'Backdate B', 'DE', 'EU', 'POINT(9 51)');
update public.profiles set is_private = false where id = '00000000-0000-0000-0000-000000000c01';
create function pg_temp.as_user() returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000c01', 'role', 'authenticated')::text, true),
         set_config('role', 'authenticated', true);
$$;
create function pg_temp.reset_role() returns void language sql as $$
  select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
$$;
create function pg_temp.occ(id uuid) returns timestamptz language sql as $$ select occurred_at from public.checkins where id = $1 $$;
create function pg_temp.sync(items jsonb) returns text language sql as $$
  select (public.sync_checkins(items) -> 'results' -> 0 ->> 'code') $$;

-- A sighting and a visit with old dates are stored as sent; a date-only entry says so
select pg_temp.as_user();
select public.sync_checkins(jsonb_build_array(
  jsonb_build_object('id', 'c0000000-0000-7000-8000-000000000001', 'kind', 'spotted', 'occurred_at', '2019-08-12T10:30:00Z', 'registration', 'DAIMA', 'time_known', true),
  jsonb_build_object('id', 'c0000000-0000-7000-8000-000000000002', 'kind', 'spotted', 'occurred_at', '2019-08-12T12:00:00Z', 'registration', 'DAIMB', 'time_known', false),
  jsonb_build_object('id', 'c0000000-0000-7000-8000-000000000003', 'kind', 'spotted', 'occurred_at', '2026-03-01T09:00:00Z', 'registration', 'DAIMC'),
  jsonb_build_object('id', 'c0000000-0000-7000-8000-000000000004', 'kind', 'airport', 'occurred_at', '2019-08-12T08:00:00Z', 'airport_id', 899001, 'context', 'spotting')));
select pg_temp.reset_role();
select is(pg_temp.occ('c0000000-0000-7000-8000-000000000001'), '2019-08-12T10:30:00Z'::timestamptz, 'a sighting keeps its old date');
select is((select time_known from public.checkins where id = 'c0000000-0000-7000-8000-000000000001'), true, 'with its time');
select is((select time_known from public.checkins where id = 'c0000000-0000-7000-8000-000000000002'), false, 'a date-only entry is marked');
select is((select time_known from public.checkins where id = 'c0000000-0000-7000-8000-000000000003'), true, 'time_known is true when the app sends nothing');
select is(pg_temp.occ('c0000000-0000-7000-8000-000000000004'), '2019-08-12T08:00:00Z'::timestamptz, 'a visit keeps its old date');

-- Dates before 1990 and in the future are refused
select pg_temp.as_user();
select is(pg_temp.sync(jsonb_build_array(jsonb_build_object('id', 'c0000000-0000-7000-8000-000000000005', 'kind', 'spotted', 'occurred_at', '1989-12-31T23:00:00Z', 'registration', 'DAIMD'))),
          'invalid_time', '1989 is refused');
select is(pg_temp.sync(jsonb_build_array(jsonb_build_object('id', 'c0000000-0000-7000-8000-000000000005', 'kind', 'spotted', 'occurred_at', (now() + interval '3 days')::text, 'registration', 'DAIMD'))),
          'invalid_time', 'next week is refused');
select pg_temp.reset_role();
select is((select count(*) from public.checkins where id = 'c0000000-0000-7000-8000-000000000005'), 0::bigint, 'and nothing is stored');

-- The edit moves a sighting and sets the flag; without time_known the flag stays
select pg_temp.as_user();
select public.sync_checkins(jsonb_build_array(
  jsonb_build_object('id', 'c0000000-0000-7000-8000-000000000001', 'kind', 'spotted', 'occurred_at', '2019-08-13T00:00:00Z', 'registration', 'DAIMA', 'time_known', false),
  jsonb_build_object('id', 'c0000000-0000-7000-8000-000000000002', 'kind', 'spotted', 'occurred_at', '2019-08-14T12:00:00Z', 'registration', 'DAIMB')));
select pg_temp.reset_role();
select is(pg_temp.occ('c0000000-0000-7000-8000-000000000001'), '2019-08-13T00:00:00Z'::timestamptz, 'the edit moves a sighting');
select is((select time_known from public.checkins where id = 'c0000000-0000-7000-8000-000000000001'), false, 'and its flag');
select is(pg_temp.occ('c0000000-0000-7000-8000-000000000002'), '2019-08-14T12:00:00Z'::timestamptz, 'a sighting is moved without a flag in the request');
select is((select time_known from public.checkins where id = 'c0000000-0000-7000-8000-000000000002'), false, 'and keeps its flag then');

-- Moving a visit moves its sightings by the same step; others stay
select pg_temp.as_user();
select public.sync_checkins(jsonb_build_array(
  jsonb_build_object('id', 'c0000000-0000-7000-8000-000000000011', 'kind', 'spotted', 'occurred_at', '2019-08-12T08:05:00Z', 'registration', 'DAIMS',
                     'visit_id', 'c0000000-0000-7000-8000-000000000004'),
  jsonb_build_object('id', 'c0000000-0000-7000-8000-000000000012', 'kind', 'spotted', 'occurred_at', '2019-08-12T08:40:00Z', 'registration', 'DAIMT',
                     'visit_id', 'c0000000-0000-7000-8000-000000000004')));
select pg_temp.reset_role();
select is((select visit_id from public.checkins where id = 'c0000000-0000-7000-8000-000000000011'), 'c0000000-0000-7000-8000-000000000004'::uuid, 'the sighting is in the visit');
select pg_temp.as_user();
select public.sync_checkins(jsonb_build_array(
  jsonb_build_object('id', 'c0000000-0000-7000-8000-000000000004', 'kind', 'airport', 'occurred_at', '2019-08-10T08:00:00Z', 'airport_id', 899001, 'context', 'spotting')));
select pg_temp.reset_role();
select is(pg_temp.occ('c0000000-0000-7000-8000-000000000004'), '2019-08-10T08:00:00Z'::timestamptz, 'the visit is moved');
select is(pg_temp.occ('c0000000-0000-7000-8000-000000000011'), '2019-08-10T08:05:00Z'::timestamptz, 'its first sighting follows by the same step');
select is(pg_temp.occ('c0000000-0000-7000-8000-000000000012'), '2019-08-10T08:40:00Z'::timestamptz, 'and its second');
select is(pg_temp.occ('c0000000-0000-7000-8000-000000000003'), '2026-03-01T09:00:00Z'::timestamptz, 'a sighting outside the visit is not moved');

-- A visit of a flight stays with the flight, whatever is sent for it alone
select pg_temp.as_user();
select public.sync_checkins(jsonb_build_array(
  jsonb_build_object('id', 'c0000000-0000-7000-8000-000000000021', 'kind', 'flown', 'occurred_at', '2026-03-01T10:00:00Z', 'origin_id', 899001, 'destination_id', 899002),
  jsonb_build_object('id', 'c0000000-0000-7000-8000-000000000022', 'kind', 'airport', 'occurred_at', '2026-03-01T10:00:00Z', 'airport_id', 899001, 'context', 'departing',
                     'flight_id', 'c0000000-0000-7000-8000-000000000021'),
  jsonb_build_object('id', 'c0000000-0000-7000-8000-000000000023', 'kind', 'airport', 'occurred_at', '2026-03-01T10:00:00Z', 'airport_id', 899002, 'context', 'arriving',
                     'flight_id', 'c0000000-0000-7000-8000-000000000021')));
select public.sync_checkins(jsonb_build_array(
  jsonb_build_object('id', 'c0000000-0000-7000-8000-000000000022', 'kind', 'airport', 'occurred_at', '2026-02-01T10:00:00Z', 'airport_id', 899001, 'context', 'departing',
                     'flight_id', 'c0000000-0000-7000-8000-000000000021', 'time_known', false)));
select pg_temp.reset_role();
select is(pg_temp.occ('c0000000-0000-7000-8000-000000000022'), '2026-03-01T10:00:00Z'::timestamptz, 'a visit of a flight is not moved on its own');
select is((select time_known from public.checkins where id = 'c0000000-0000-7000-8000-000000000022'), true, 'nor its flag');

-- The readers return time_known
select pg_temp.as_user();
select is((select time_known from public.get_checkin('c0000000-0000-7000-8000-000000000002')), false, 'get_checkin returns the flag');
select is((select time_known from public.get_my_checkins(null, null, 200) where id = 'c0000000-0000-7000-8000-000000000002'), false, 'get_my_checkins too');
select is((select time_known from public.get_feed(null, null, 50, 'created') where id = 'c0000000-0000-7000-8000-000000000002'), false, 'get_feed too');
select is((select time_known from public.get_visit_sightings('c0000000-0000-7000-8000-000000000004') limit 1), true, 'get_visit_sightings too');
select pg_temp.reset_role();

-- Badges follow the event date: a Saturday sighting counts for the weekend, moved to Friday it does not (a second person, so
-- the dates above do not count)
insert into auth.users (id, aud, role, email) values
  ('00000000-0000-0000-0000-000000000c02', 'authenticated', 'authenticated', 'backdate2@example.test');
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000c02', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);
select public.sync_checkins(jsonb_build_array(
  jsonb_build_object('id', 'c0000000-0000-7000-8000-000000000031', 'kind', 'spotted', 'occurred_at', '2026-03-07T12:00:00Z', 'registration', 'DAIMW', 'airport_id', 899001)));
select pg_temp.reset_role();
select is((select progress from public.user_badges where user_id = '00000000-0000-0000-0000-000000000c02' and badge_id = 'weekend_warrior'), 1,
          'a sighting dated on a Saturday counts for the weekend badge');
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000c02', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);
select public.sync_checkins(jsonb_build_array(
  jsonb_build_object('id', 'c0000000-0000-7000-8000-000000000031', 'kind', 'spotted', 'occurred_at', '2026-03-06T12:00:00Z', 'registration', 'DAIMW', 'airport_id', 899001)));
select pg_temp.reset_role();
select is((select progress from public.user_badges where user_id = '00000000-0000-0000-0000-000000000c02' and badge_id = 'weekend_warrior'), 0,
          'moved to the Friday, the badges are worked out again and the weekend is gone');

-- The access test lists no new function; the readers keep their grants
select ok(has_function_privilege('authenticated', 'public.get_feed(timestamptz, uuid, integer, text)', 'execute'), 'get_feed is still callable by signed-in people');
select ok(not has_function_privilege('anon', 'public.get_feed(timestamptz, uuid, integer, text)', 'execute'), 'and not by anon');

select * from finish();
rollback;
