-- Spotting locations and sessions: adding a place, the numbers, and linking sightings to a visit.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

-- 1 = spotter, 2 = another spotter, 3 = a stranger with a private profile who has a public visit too
insert into auth.users (id, aud, role, email)
select ('00000000-0000-0000-0000-0000000009' || lpad(n::text, 2, '0'))::uuid, 'authenticated', 'authenticated', 'spot' || n || '@example.test'
from generate_series(1, 3) n;
create function pg_temp.u(n integer) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000009' || lpad(n::text, 2, '0'))::uuid;
$$;
create function pg_temp.as_user(n integer) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true),
         set_config('role', 'authenticated', true);
$$;
create function pg_temp.reset_role() returns void language sql as $$
  select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
$$;
insert into public.airports (id, icao, iata, name, country_code, continent, location) values
  (897001, 'ZZSA', 'ZSA', 'Spot airport A', 'DE', 'EU', 'POINT(8 50)'),
  (897002, 'ZZSB', 'ZSB', 'Spot airport B', 'DE', 'EU', 'POINT(8.5 50)');
update public.profiles set is_private = false where id in (pg_temp.u(1), pg_temp.u(2), pg_temp.u(3));

-- Adding a place ----------------------------------------------------------------------------------------------
select pg_temp.as_user(1);
select is((public.add_spotting_location('Visitor deck', 50.001, 8.001, 'Great view', 'Morning', 'South', 'Bring a jacket') ->> 'status'),
  'pending', 'a new place waits for approval');
select is((select airport_id from public.spotting_locations where name = 'Visitor deck'), 897001,
  'its airport is the nearest one to the pin');
select is((public.add_spotting_location('Visitor deck', 50.0011, 8.0011) ->> 'status'), 'duplicate',
  'the same name within 100 m is reported, not added again');
select is((public.add_spotting_location('Far away hill', -40, -100) ->> 'code'), 'no_airport_nearby',
  'a pin with no airport within 150 km is refused');
select is((public.add_spotting_location('x', 50, 8) ->> 'code'), 'invalid_name', 'a name needs 3 to 80 characters');
select is((public.add_spotting_location('Bad pin', 91, 8) ->> 'code'), 'invalid_location', 'and a real position');

-- Only the author sees it until it is approved
select is((select count(*)::int from public.spotting_locations_at(897001)), 1, 'the author sees the waiting place');
select is((select mine from public.spotting_locations_at(897001)), true, 'marked as theirs');
select pg_temp.reset_role();
select pg_temp.as_user(2);
select is((select count(*)::int from public.spotting_locations_at(897001)), 0, 'others do not see it yet');
select is(public.get_spotting_location((select id from public.spotting_locations where name = 'Visitor deck')), null, 'nor open it');
select pg_temp.reset_role();
update public.spotting_locations set status = 'approved' where name = 'Visitor deck';
select pg_temp.as_user(2);
select is((select count(*)::int from public.spotting_locations_at(897001)), 1, 'once approved everyone sees it');
select is((public.get_spotting_location((select id from public.spotting_locations where name = 'Visitor deck')) ->> 'iata'), 'ZSA', 'with its airport');
select pg_temp.reset_role();

-- Ten waiting at a time
select pg_temp.as_user(3);
select lives_ok($$ select public.add_spotting_location('Place ' || n, 50.01 + n * 0.01, 8.0) from generate_series(1, 10) n $$, 'ten can wait');
select is((public.add_spotting_location('Place eleven', 50.5, 8.0) ->> 'code'), 'too_many_pending', 'the eleventh is refused');
select pg_temp.reset_role();

-- Sessions: a visit at the place, and sightings linked to it -----------------------------------------------------
select pg_temp.as_user(2);
select public.sync_checkins(jsonb_build_array(
  jsonb_build_object('id', 'a9000000-0000-7000-8000-000000000001', 'kind', 'airport', 'occurred_at', '2026-03-01T08:00:00Z',
                     'airport_id', 897001, 'context', 'spotting', 'visibility', 'public',
                     'spot_location_id', (select id from public.spotting_locations where name = 'Visitor deck')),
  jsonb_build_object('id', 'a9000000-0000-7000-8000-000000000002', 'kind', 'spotted', 'occurred_at', '2026-03-01T08:10:00Z',
                     'registration', 'D-AAAA', 'visibility', 'public', 'visit_id', 'a9000000-0000-7000-8000-000000000001'),
  jsonb_build_object('id', 'a9000000-0000-7000-8000-000000000003', 'kind', 'spotted', 'occurred_at', '2026-03-01T08:20:00Z',
                     'registration', 'D-AAAB', 'visibility', 'friends', 'visit_id', 'a9000000-0000-7000-8000-000000000001')));
select pg_temp.reset_role();
select is((select spot_location_id from public.checkins where id = 'a9000000-0000-7000-8000-000000000001'),
  (select id from public.spotting_locations where name = 'Visitor deck'), 'the visit names its place');
select is((select count(*)::int from public.checkins where visit_id = 'a9000000-0000-7000-8000-000000000001'), 2,
  'both sightings are linked to the visit');

-- A place at another airport, or one that is not approved, is dropped; the visit is still stored
select pg_temp.as_user(2);
select public.sync_checkins(jsonb_build_array(
  jsonb_build_object('id', 'a9000000-0000-7000-8000-000000000004', 'kind', 'airport', 'occurred_at', '2026-03-02T08:00:00Z',
                     'airport_id', 897002, 'context', 'spotting', 'visibility', 'public',
                     'spot_location_id', (select id from public.spotting_locations where name = 'Visitor deck')),
  jsonb_build_object('id', 'a9000000-0000-7000-8000-000000000005', 'kind', 'spotted', 'occurred_at', '2026-03-02T08:10:00Z',
                     'registration', 'D-AAAC', 'visibility', 'public', 'visit_id', 'a9000000-0000-7000-8000-0000000000ff')));
select pg_temp.reset_role();
select is((select spot_location_id from public.checkins where id = 'a9000000-0000-7000-8000-000000000004'), null,
  'a place at another airport is dropped');
select is((select count(*)::int from public.checkins where id = 'a9000000-0000-7000-8000-000000000004'), 1, 'the visit itself is stored');
select is((select visit_id from public.checkins where id = 'a9000000-0000-7000-8000-000000000005'), null,
  'a visit that does not exist is dropped, the sighting is kept');

-- Someone else's visit cannot be claimed
select pg_temp.as_user(3);
select public.sync_checkins(jsonb_build_array(
  jsonb_build_object('id', 'a9000000-0000-7000-8000-000000000006', 'kind', 'spotted', 'occurred_at', '2026-03-03T08:10:00Z',
                     'registration', 'D-AAAD', 'visibility', 'public', 'visit_id', 'a9000000-0000-7000-8000-000000000001')));
select pg_temp.reset_role();
select is((select visit_id from public.checkins where id = 'a9000000-0000-7000-8000-000000000006'), null,
  'someone else''s visit cannot be linked to');

-- Reading: the aircraft of a session, as far as the viewer may see them
select pg_temp.as_user(2);
select is((select count(*)::int from public.get_visit_sightings('a9000000-0000-7000-8000-000000000001')), 2, 'the owner sees every sighting');
select pg_temp.reset_role();
select pg_temp.as_user(3);
select is((select count(*)::int from public.get_visit_sightings('a9000000-0000-7000-8000-000000000001')), 1,
  'a stranger sees only the public one');
select is((public.get_spotting_location((select id from public.spotting_locations where name = 'Visitor deck')) ->> 'sessions'), '1',
  'the place counts its public sessions');
select is((public.get_spotting_location((select id from public.spotting_locations where name = 'Visitor deck')) ->> 'aircraft'), '1',
  'and the public aircraft seen there');
select is((public.get_spotting_location((select id from public.spotting_locations where name = 'Visitor deck')) ->> 'my_sessions'), '0',
  'and your own sessions');
select pg_temp.reset_role();

-- Deleting a visit unlinks its sightings
delete from public.checkins where id = 'a9000000-0000-7000-8000-000000000001';
select is((select count(*)::int from public.checkins where id = 'a9000000-0000-7000-8000-000000000002' and visit_id is null), 1,
  'a sighting stays when its visit is deleted');
select pg_temp.as_user(2);
select is((select count(*)::int from public.get_visit_sightings('a9000000-0000-7000-8000-000000000001')), 0, 'and is no longer listed');
select pg_temp.reset_role();

select finish();
rollback;
