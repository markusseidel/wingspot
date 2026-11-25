-- Companion Sync (#273): open requests, the same-flight match, keep mine, replace the flight data, the source of a copy.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

insert into auth.users (id, aud, role, email)
select format('00000000-0000-0000-0000-0000000000%s', n)::uuid, 'authenticated', 'authenticated', format('companion%s@example.test', n)
from unnest(array['e1','e2','e3']) n;
-- e1 (author) and e2 (companion) are mutual friends; e3 is a stranger.
insert into public.follows (follower, followee) values
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000e2'), ('00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000000e1');
insert into public.airports (id, icao, iata, name, country_code, continent, location) values
  (896001, 'ZZCA', 'ZCA', 'Companion A', 'DE', 'EU', 'POINT(8 50)'),
  (896002, 'ZZCB', 'ZCB', 'Companion B', 'US', 'NA', 'POINT(-73 40)'),
  (896003, 'ZZCC', 'ZCC', 'Companion C', 'GB', 'EU', 'POINT(0 51)');

create function pg_temp.as_user(u text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', ('00000000-0000-0000-0000-0000000000' || u)::uuid, 'role', 'authenticated')::text, true),
         set_config('role', 'authenticated', true);
$$;
create function pg_temp.reset_role() returns void language sql as $$
  select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
$$;

-- e1 logs a flight (with its two visits) and a standalone visit, tagging e2 on both
select pg_temp.as_user('e1');
select public.sync_checkins(jsonb_build_array(
  jsonb_build_object('id', 'e0000000-0000-7000-8000-000000000001', 'kind', 'flown', 'occurred_at', '2026-08-12T12:00:00Z', 'flight_number', 'LH400',
    'origin_id', 896001, 'destination_id', 896002, 'with', jsonb_build_array('00000000-0000-0000-0000-0000000000e2')),
  jsonb_build_object('id', 'e0000000-0000-7000-8000-000000000002', 'kind', 'airport', 'occurred_at', '2026-08-12T12:00:00Z', 'airport_id', 896001,
    'context', 'departing', 'flight_id', 'e0000000-0000-7000-8000-000000000001'),
  jsonb_build_object('id', 'e0000000-0000-7000-8000-000000000003', 'kind', 'airport', 'occurred_at', '2026-08-12T12:00:00Z', 'airport_id', 896002,
    'context', 'arriving', 'flight_id', 'e0000000-0000-7000-8000-000000000001'),
  jsonb_build_object('id', 'e0000000-0000-7000-8000-000000000004', 'kind', 'airport', 'occurred_at', '2026-08-13T09:00:00Z', 'airport_id', 896003,
    'context', 'spotting', 'with', jsonb_build_array('00000000-0000-0000-0000-0000000000e2'))));

-- Requests: e2 has two open ones (the flight and the standalone visit, not the flight's own visits); the author and a stranger have none
select pg_temp.as_user('e2');
select is((select count(*)::int from public.get_companion_requests()), 2, 'the tagged friend has two requests');
select is((select count(*)::int from public.get_companion_requests() where checkin_id = 'e0000000-0000-7000-8000-000000000001' and flight_number = 'LH400' and origin_code = 'ZCA' and destination_code = 'ZCB'),
          1, 'the flight request has its number and route');
select pg_temp.as_user('e1');
select is((select count(*)::int from public.get_companion_requests()), 0, 'the author has no request');
select pg_temp.as_user('e3');
select is((select count(*)::int from public.get_companion_requests()), 0, 'a stranger has none');

-- The same flight: e2 has already logged LH400 on the same day, and a flight on the same route 6 hours away, and another route
select pg_temp.reset_role();
insert into public.checkins (id, user_id, kind, occurred_at, origin_id, destination_id, flight_number) values
  ('e0000000-0000-7000-8000-000000000011', '00000000-0000-0000-0000-0000000000e2', 'flown', '2026-08-12T13:00:00Z', 896001, 896002, 'LH 400'),
  ('e0000000-0000-7000-8000-000000000012', '00000000-0000-0000-0000-0000000000e2', 'flown', '2026-08-12T18:00:00Z', 896001, 896002, 'UA900'),
  ('e0000000-0000-7000-8000-000000000013', '00000000-0000-0000-0000-0000000000e2', 'flown', '2026-08-12T12:00:00Z', 896001, 896003, 'LH400'),
  ('e0000000-0000-7000-8000-000000000014', '00000000-0000-0000-0000-0000000000e2', 'flown', '2026-08-30T12:00:00Z', 896001, 896002, 'LH400');
select pg_temp.as_user('e2');
select is((select array_agg(id order by id)::text from public.find_matching_flight('e0000000-0000-7000-8000-000000000001')),
          '{e0000000-0000-7000-8000-000000000011,e0000000-0000-7000-8000-000000000012,e0000000-0000-7000-8000-000000000013}',
          'LH400 the same day, the codeshare on the same route within 12 hours, and the same number on another route are found; a flight weeks later is not');
select is((select id from public.find_matching_flight('e0000000-0000-7000-8000-000000000001') limit 1), 'e0000000-0000-7000-8000-000000000011'::uuid, 'the flight with the same number and the same route comes first');
select is((select reason from public.find_matching_flight('e0000000-0000-7000-8000-000000000001') where id = 'e0000000-0000-7000-8000-000000000012'), 'route', 'the codeshare is found by its route');
select pg_temp.as_user('e3');
select is((select count(*)::int from public.find_matching_flight('e0000000-0000-7000-8000-000000000001')), 0, 'a stranger gets no match');

-- Keep mine: link the flight e2 has to the source. A stranger, a wrong kind and a second link are refused.
select pg_temp.as_user('e3');
select is(public.link_companion('e0000000-0000-7000-8000-000000000011', 'e0000000-0000-7000-8000-000000000001'), false, 'a stranger cannot link');
select pg_temp.as_user('e2');
select is(public.link_companion('e0000000-0000-7000-8000-000000000011', 'e0000000-0000-7000-8000-000000000004'), false, 'a flight cannot be linked to a visit');
select is(public.link_companion('e0000000-0000-7000-8000-000000000011', 'e0000000-0000-7000-8000-000000000001'), true, 'the tagged friend links the flight they have');
select is(public.link_companion('e0000000-0000-7000-8000-000000000012', 'e0000000-0000-7000-8000-000000000001'), false, 'a second check-in cannot take the same source');
select is(public.link_companion('e0000000-0000-7000-8000-000000000011', 'e0000000-0000-7000-8000-000000000001'), true, 'linking the same pair again is fine');
select is((select count(*)::int from public.get_companion_requests()), 1, 'the linked flight is no longer a request');
select is((select user_id from public.get_checkin_source('e0000000-0000-7000-8000-000000000011')), '00000000-0000-0000-0000-0000000000e1'::uuid, 'the copy knows whose flight it came from');
select pg_temp.as_user('e1');
select is((select count(*)::int from public.get_checkin_source('e0000000-0000-7000-8000-000000000011')), 0, 'only the owner of the copy asks for its source');
select is((select count(*)::int from public.get_checkin_copies('e0000000-0000-7000-8000-000000000001')), 1, 'and the author sees who took the flight over');
select pg_temp.as_user('e2');
-- the match no longer offers a flight that points at this source twice, and flights linked to another source are left out
select is((select count(*)::int from public.find_matching_flight('e0000000-0000-7000-8000-000000000001') where id = 'e0000000-0000-7000-8000-000000000011'), 1, 'the linked flight is still found for its own source');

-- Replace the flight data: e1 logs a second flight and tags e2; e2 has a flight of their own with a seat, on another route and day, with visits
select pg_temp.reset_role();
insert into public.checkins (id, user_id, kind, occurred_at, origin_id, destination_id, flight_number) values
  ('e0000000-0000-7000-8000-000000000005', '00000000-0000-0000-0000-0000000000e1', 'flown', '2026-09-01T12:00:00Z', 896001, 896002, 'LH500');
insert into public.checkin_tags (checkin_id, user_id) values ('e0000000-0000-7000-8000-000000000005', '00000000-0000-0000-0000-0000000000e2');
insert into public.checkins (id, user_id, kind, occurred_at, origin_id, destination_id, flight_number, seat, cabin_class, visibility) values
  ('e0000000-0000-7000-8000-000000000021', '00000000-0000-0000-0000-0000000000e2', 'flown', '2026-08-11T12:00:00Z', 896001, 896003, 'XX1', '12A', 'economy', 'friends'),
  ('e0000000-0000-7000-8000-000000000022', '00000000-0000-0000-0000-0000000000e2', 'airport', '2026-08-11T12:00:00Z', null, null, null, null, null, 'friends');
update public.checkins set airport_id = 896001, visit_context = 'departing', flight_id = 'e0000000-0000-7000-8000-000000000021' where id = 'e0000000-0000-7000-8000-000000000022';
insert into public.checkins (id, user_id, kind, occurred_at, airport_id, visit_context, flight_id, visibility) values
  ('e0000000-0000-7000-8000-000000000023', '00000000-0000-0000-0000-0000000000e2', 'airport', '2026-08-11T12:00:00Z', 896003, 'arriving', 'e0000000-0000-7000-8000-000000000021', 'friends');
insert into public.comments (id, checkin_id, user_id, body) values
  ('e0000000-0000-7000-8000-0000000000c1', 'e0000000-0000-7000-8000-000000000021', '00000000-0000-0000-0000-0000000000e1', 'nice')
on conflict do nothing;
select pg_temp.as_user('e3');
select is(public.replace_flight_data('e0000000-0000-7000-8000-000000000021', 'e0000000-0000-7000-8000-000000000005'), null, 'a stranger cannot replace anything');
select pg_temp.as_user('e2');
select is(public.replace_flight_data('e0000000-0000-7000-8000-000000000021', 'e0000000-0000-7000-8000-000000000004'), null, 'a visit is not a flight');
select is(public.replace_flight_data('e0000000-0000-7000-8000-000000000021', 'e0000000-0000-7000-8000-000000000005') ->> 'flight_number', 'LH500', 'the tagged friend replaces the flight data and gets the new facts back');
select pg_temp.reset_role();
select is((select flight_number || ' ' || origin_id || ' ' || destination_id || ' ' || occurred_at::date from public.checkins where id = 'e0000000-0000-7000-8000-000000000021'),
          'LH500 896001 896002 2026-09-01', 'the flight has the number, route and day of the source');
select ok((select distance_km > 5000 from public.checkins where id = 'e0000000-0000-7000-8000-000000000021'), 'and a distance worked out for the new route');
select is((select seat || ' ' || cabin_class::text || ' ' || visibility from public.checkins where id = 'e0000000-0000-7000-8000-000000000021'), '12A economy friends', 'the seat, cabin and visibility stay');
select is((select source_checkin_id from public.checkins where id = 'e0000000-0000-7000-8000-000000000021'), 'e0000000-0000-7000-8000-000000000005'::uuid, 'the flight is linked to the source');
select is((select airport_id from public.checkins where id = 'e0000000-0000-7000-8000-000000000023'), 896002, 'its arrival visit moved to the new destination');
select is((select occurred_at::date from public.checkins where id = 'e0000000-0000-7000-8000-000000000023'), '2026-09-01'::date, 'and to the new day');
select is((select count(*)::int from public.comments where checkin_id = 'e0000000-0000-7000-8000-000000000021'), 1, 'the comments stay');

select * from finish();
rollback;
