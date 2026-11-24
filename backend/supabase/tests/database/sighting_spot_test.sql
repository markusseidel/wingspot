-- A sighting names its own spotting place (issue #286): kept, validated, edited, shown and listed.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

insert into auth.users (id, aud, role, email)
select ('00000000-0000-0000-0000-0000000008' || lpad(n::text, 2, '0'))::uuid, 'authenticated', 'authenticated', 'sspot' || n || '@example.test'
from generate_series(1, 3) n;
create function pg_temp.u(n integer) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000008' || lpad(n::text, 2, '0'))::uuid;
$$;
create function pg_temp.as_user(n integer) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true),
         set_config('role', 'authenticated', true);
$$;
create function pg_temp.reset_role() returns void language sql as $$
  select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
$$;
insert into public.airports (id, icao, iata, name, country_code, continent, location) values
  (898001, 'ZZSC', 'ZSC', 'Sighting airport A', 'DE', 'EU', 'POINT(8 50)'),
  (898002, 'ZZSD', 'ZSD', 'Sighting airport B', 'DE', 'EU', 'POINT(8.5 50)');
update public.profiles set is_private = false where id in (pg_temp.u(1), pg_temp.u(2), pg_temp.u(3));
insert into public.spotting_locations (id, airport_id, name, location, status, created_by) values
  (898101, 898001, 'North deck', 'POINT(8.001 50.001)', 'approved', pg_temp.u(1)),
  (898102, 898001, 'Hill', 'POINT(8.002 50.002)', 'approved', pg_temp.u(1)),
  (898103, 898002, 'Other airport deck', 'POINT(8.5 50.001)', 'approved', pg_temp.u(1)),
  (898104, 898001, 'Waiting place', 'POINT(8.003 50.003)', 'pending', pg_temp.u(3));

-- A direct place is kept; one at another airport or someone else's waiting one is dropped, the sighting is stored anyway
select pg_temp.as_user(1);
select public.sync_checkins(jsonb_build_array(
  jsonb_build_object('id', 'b8000000-0000-7000-8000-000000000001', 'kind', 'spotted', 'occurred_at', '2026-04-01T08:00:00Z', 'registration', 'D-SPA1',
                     'airport_id', 898001, 'visibility', 'public', 'spot_location_id', 898101),
  jsonb_build_object('id', 'b8000000-0000-7000-8000-000000000002', 'kind', 'spotted', 'occurred_at', '2026-04-01T08:10:00Z', 'registration', 'D-SPA2',
                     'airport_id', 898001, 'visibility', 'public', 'spot_location_id', 898103),
  jsonb_build_object('id', 'b8000000-0000-7000-8000-000000000003', 'kind', 'spotted', 'occurred_at', '2026-04-01T08:20:00Z', 'registration', 'D-SPA3',
                     'airport_id', 898001, 'visibility', 'public', 'spot_location_id', 898104),
  jsonb_build_object('id', 'b8000000-0000-7000-8000-000000000004', 'kind', 'spotted', 'occurred_at', '2026-04-01T08:30:00Z', 'registration', 'D-SPA4',
                     'visibility', 'public', 'spot_location_id', 898101),
  jsonb_build_object('id', 'b8000000-0000-7000-8000-000000000005', 'kind', 'spotted', 'occurred_at', '2026-04-01T08:40:00Z', 'registration', 'D-SPA5',
                     'airport_id', 898001, 'visibility', 'private', 'spot_location_id', 898101)));
select pg_temp.reset_role();
select is((select spot_location_id from public.checkins where id = 'b8000000-0000-7000-8000-000000000001'), 898101, 'a sighting keeps its own place');
select is((select spot_location_id from public.checkins where id = 'b8000000-0000-7000-8000-000000000002'), null, 'a place at another airport is dropped');
select is((select count(*)::int from public.checkins where id = 'b8000000-0000-7000-8000-000000000002'), 1, 'and the sighting is stored anyway');
select is((select spot_location_id from public.checkins where id = 'b8000000-0000-7000-8000-000000000003'), null, 'someone else''s waiting place is dropped');
select is((select spot_location_id from public.checkins where id = 'b8000000-0000-7000-8000-000000000004'), null, 'a sighting without an airport keeps no place');

-- Reading: "Spotted at"
select pg_temp.as_user(1);
select is((public.get_checkin_spot('b8000000-0000-7000-8000-000000000001') ->> 'spot_name'), 'North deck', 'the check-in page says where it was spotted');
select is((public.get_checkin_spot('b8000000-0000-7000-8000-000000000002')), null, 'a sighting without a place has no answer');

-- Edit: set, change, keep when the field is absent, clear with null
select public.sync_checkins(jsonb_build_array(
  jsonb_build_object('id', 'b8000000-0000-7000-8000-000000000002', 'kind', 'spotted', 'occurred_at', '2026-04-01T08:10:00Z', 'registration', 'D-SPA2',
                     'airport_id', 898001, 'visibility', 'public', 'spot_location_id', 898102)));
select pg_temp.reset_role();
select is((select spot_location_id from public.checkins where id = 'b8000000-0000-7000-8000-000000000002'), 898102, 'an older sighting can get a place in the edit');
select pg_temp.as_user(1);
select public.sync_checkins(jsonb_build_array(
  jsonb_build_object('id', 'b8000000-0000-7000-8000-000000000002', 'kind', 'spotted', 'occurred_at', '2026-04-01T08:10:00Z', 'registration', 'D-SPA2',
                     'airport_id', 898001, 'visibility', 'public')));
select pg_temp.reset_role();
select is((select spot_location_id from public.checkins where id = 'b8000000-0000-7000-8000-000000000002'), 898102, 'an app that does not send the field leaves the place as it was');
select pg_temp.as_user(1);
select public.sync_checkins(jsonb_build_array(
  jsonb_build_object('id', 'b8000000-0000-7000-8000-000000000002', 'kind', 'spotted', 'occurred_at', '2026-04-01T08:10:00Z', 'registration', 'D-SPA2',
                     'airport_id', 898001, 'visibility', 'public', 'spot_location_id', null)));
select pg_temp.reset_role();
select is((select spot_location_id from public.checkins where id = 'b8000000-0000-7000-8000-000000000002'), null, 'null clears it');
-- the airport visit's place is not touched by this
select pg_temp.as_user(1);
select public.sync_checkins(jsonb_build_array(
  jsonb_build_object('id', 'b8000000-0000-7000-8000-000000000002', 'kind', 'spotted', 'occurred_at', '2026-04-01T08:10:00Z', 'registration', 'D-SPA2',
                     'airport_id', 898001, 'visibility', 'public', 'spot_location_id', 898102)));
select pg_temp.reset_role();

-- The sighting's own place wins over the session's
select pg_temp.as_user(2);
select public.sync_checkins(jsonb_build_array(
  jsonb_build_object('id', 'b8000000-0000-7000-8000-0000000000a1', 'kind', 'airport', 'occurred_at', '2026-04-02T08:00:00Z',
                     'airport_id', 898001, 'context', 'spotting', 'visibility', 'public', 'spot_location_id', 898101),
  jsonb_build_object('id', 'b8000000-0000-7000-8000-0000000000a2', 'kind', 'spotted', 'occurred_at', '2026-04-02T08:10:00Z', 'registration', 'D-SPB1',
                     'visibility', 'public', 'visit_id', 'b8000000-0000-7000-8000-0000000000a1'),
  jsonb_build_object('id', 'b8000000-0000-7000-8000-0000000000a3', 'kind', 'spotted', 'occurred_at', '2026-04-02T08:20:00Z', 'registration', 'D-SPB2',
                     'airport_id', 898001, 'visibility', 'public', 'visit_id', 'b8000000-0000-7000-8000-0000000000a1', 'spot_location_id', 898102)));
select is((public.get_checkin_spot('b8000000-0000-7000-8000-0000000000a2') ->> 'spot_name'), 'North deck', 'a sighting in a session shows the session''s place');
select is((public.get_checkin_spot('b8000000-0000-7000-8000-0000000000a3') ->> 'spot_name'), 'Hill', 'and its own place wins when it has one');
select pg_temp.reset_role();

-- The place page: counts and the list, public only, each sighting once
select pg_temp.as_user(3);
select is((public.get_spotting_location(898101) ->> 'aircraft'), '2', 'North deck: one direct and one through the session, public only');
select is((public.get_spotting_location(898102) ->> 'aircraft'), '2', 'Hill: the edited one and the session sighting with its own place');
select is((select string_agg(registration, ',' order by registration) from public.get_spot_sightings(898101)), 'D-SPA1,D-SPB1', 'the list shows the same public sightings');
select is((select count(*)::int from public.get_spot_sightings(898101) where registration = 'D-SPA5'), 0, 'a private sighting is not listed for others');
select is((select count(*)::int from public.get_spot_sightings(898104)), 0, 'a waiting place of someone else has no list');
select is((select count(*)::int from public.get_spot_sightings(898101, 1)), 1, 'the limit applies');
select is((select registration from public.get_spot_sightings(898101, 1, (select occurred_at from public.get_spot_sightings(898101, 1)), (select id from public.get_spot_sightings(898101, 1)))), 'D-SPA1', 'and paging goes on from the last row');
select pg_temp.reset_role();
select pg_temp.as_user(1);
select is((select count(*)::int from public.get_spot_sightings(898101) where registration = 'D-SPA5'), 1, 'the owner sees their own private one');
select pg_temp.reset_role();
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';
select throws_ok($$ select * from public.get_spot_sightings(898101) $$, '42501', null, 'signed-out users cannot list');

select * from finish();
rollback;
