-- One feed entry per flight, and the flight carries its badges (issues #255 and #256).
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

insert into auth.users (id, aud, role, email) values
  ('00000000-0000-0000-0000-0000000000f1', 'authenticated', 'authenticated', 'flightfeed1@example.test'),
  ('00000000-0000-0000-0000-0000000000f2', 'authenticated', 'authenticated', 'flightfeed2@example.test');
insert into public.airports (id, icao, iata, name, country_code, continent, location) values
  (897001, 'ZZZP', 'ZZP', 'Flight feed A', 'DE', 'EU', 'POINT(8 50)'),
  (897002, 'ZZZQ', 'ZZQ', 'Flight feed B', 'DE', 'EU', 'POINT(9 51)');
-- f2 follows f1 and reads the feed
insert into public.follows (follower, followee) values ('00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-0000000000f1');
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000f1', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);

-- A flight with its two visits (new app: visits carry flight_id), made visible to followers
select public.sync_checkins(jsonb_build_array(
  jsonb_build_object('id', 'f0000000-0000-7000-8000-000000000001', 'kind', 'flown', 'occurred_at', '2026-03-01T10:00:00Z', 'origin_id', 897001, 'destination_id', 897002, 'visibility', 'public'),
  jsonb_build_object('id', 'f0000000-0000-7000-8000-000000000002', 'kind', 'airport', 'occurred_at', '2026-03-01T10:00:00Z', 'airport_id', 897001, 'context', 'departing', 'flight_id', 'f0000000-0000-7000-8000-000000000001', 'visibility', 'public'),
  jsonb_build_object('id', 'f0000000-0000-7000-8000-000000000003', 'kind', 'airport', 'occurred_at', '2026-03-01T10:00:00Z', 'airport_id', 897002, 'context', 'arriving', 'flight_id', 'f0000000-0000-7000-8000-000000000001', 'visibility', 'public')));
-- The other rows come later, so the first upload's badges are decided by the flight alone
select public.sync_checkins(jsonb_build_array(
  -- a visit on its own, at another time
  jsonb_build_object('id', 'f0000000-0000-7000-8000-000000000004', 'kind', 'airport', 'occurred_at', '2026-03-05T10:00:00Z', 'airport_id', 897001, 'context', 'spotting', 'visibility', 'public'),
  -- an old-style visit without the link, at a flight's time and airport
  jsonb_build_object('id', 'f0000000-0000-7000-8000-000000000005', 'kind', 'flown', 'occurred_at', '2026-04-01T10:00:00Z', 'origin_id', 897001, 'destination_id', 897002, 'visibility', 'public'),
  jsonb_build_object('id', 'f0000000-0000-7000-8000-000000000006', 'kind', 'airport', 'occurred_at', '2026-04-01T10:00:00Z', 'airport_id', 897002, 'context', 'arriving', 'visibility', 'public'),
  -- a visit that says it belongs to a flight the server never got: it stays a feed entry
  jsonb_build_object('id', 'f0000000-0000-7000-8000-000000000007', 'kind', 'airport', 'occurred_at', '2026-05-01T10:00:00Z', 'airport_id', 897001, 'context', 'departing', 'flight_id', 'f0000000-0000-7000-8000-0000000000ff', 'visibility', 'public')));

select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000f2', 'role', 'authenticated')::text, true);
select is((select string_agg(id::text, ',' order by id) from public.get_feed(null, null, 50, 'occurred') where user_id = '00000000-0000-0000-0000-0000000000f1'),
  'f0000000-0000-7000-8000-000000000001,f0000000-0000-7000-8000-000000000004,f0000000-0000-7000-8000-000000000005,f0000000-0000-7000-8000-000000000007',
  'the feed has the flights, the standalone visit and the orphan visit, and not the visits of a flight (with or without the link)');
select is((select count(*)::int from public.get_feed(null, null, 50, 'created') where user_id = '00000000-0000-0000-0000-0000000000f1'), 4, 'the same when sorted by check-in time');

-- The visits are still stored
select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
select is((select count(*)::int from public.checkins where user_id = '00000000-0000-0000-0000-0000000000f1'), 7, 'all seven rows are stored');

-- Badges: the first flight earned its badges on the flight, not on a visit
select is((select checkin_id from public.user_badges where user_id = '00000000-0000-0000-0000-0000000000f1' and badge_id = 'wheels_up'),
  'f0000000-0000-7000-8000-000000000001'::uuid, 'a badge of a flight check-in is tied to the flight, not to one of its visits');

-- A badge that sits on a visit moves to the flight (what the migration did to existing data)
update public.user_badges set checkin_id = 'f0000000-0000-7000-8000-000000000003' where user_id = '00000000-0000-0000-0000-0000000000f1' and badge_id = 'wheels_up';
select is(private.is_flight_visit('f0000000-0000-7000-8000-000000000003'), true, 'a linked visit is a flight visit');
select is(private.is_flight_visit('f0000000-0000-7000-8000-000000000006'), true, 'so is an old-style visit at a flight''s time and airport');
select is(private.is_flight_visit('f0000000-0000-7000-8000-000000000004'), false, 'a standalone visit is not');
select is(private.is_flight_visit('f0000000-0000-7000-8000-000000000007'), false, 'a visit of a flight the server never got is not');
select is(private.is_flight_visit('f0000000-0000-7000-8000-000000000001'), false, 'a flight is not');

-- A standalone airport check-in keeps its own badges
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000f2', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);
select public.sync_checkins(jsonb_build_array(
  jsonb_build_object('id', 'f0000000-0000-7000-8000-000000000011', 'kind', 'airport', 'occurred_at', '2026-03-02T10:00:00Z', 'airport_id', 897001, 'context', 'spotting', 'visibility', 'public')));
select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
select is((select checkin_id from public.user_badges where user_id = '00000000-0000-0000-0000-0000000000f2' and badge_id = 'wheels_up'),
  'f0000000-0000-7000-8000-000000000011'::uuid, 'a standalone airport check-in keeps its badge');

select * from finish();
rollback;
