-- Adding a friend's check-in to your own logbook, and the Wingman badge.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

insert into auth.users (id, aud, role, email)
select format('00000000-0000-0000-0000-0000000000%s', n)::uuid, 'authenticated', 'authenticated', format('copy%s@example.test', n)
from unnest(array['d1','d2','d3']) n;
insert into public.follows (follower, followee) values
  ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000d2'), ('00000000-0000-0000-0000-0000000000d2', '00000000-0000-0000-0000-0000000000d1'),
  ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000d3'), ('00000000-0000-0000-0000-0000000000d3', '00000000-0000-0000-0000-0000000000d1');
insert into public.airports (id, icao, iata, name, country_code, continent, location) values
  (897001, 'ZZZO', 'ZZO', 'Copy A', 'DE', 'EU', 'POINT(8 50)'), (897002, 'ZZZP', 'ZZP', 'Copy B', 'DE', 'EU', 'POINT(9 51)');

-- d1 tags d2 on a flight, but not d3
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000d1', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);
select public.sync_checkins(jsonb_build_array(jsonb_build_object(
  'id', 'd0000000-0000-7000-8000-000000000001', 'kind', 'flown', 'occurred_at', '2026-03-01T10:00:00Z',
  'origin_id', 897001, 'destination_id', 897002, 'with', jsonb_build_array('00000000-0000-0000-0000-0000000000d2'))));

-- d2 adds it to their logbook, and so tries to d3 without being tagged
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000d2', 'role', 'authenticated')::text, true);
select public.sync_checkins(jsonb_build_array(jsonb_build_object(
  'id', 'd0000000-0000-7000-8000-000000000002', 'kind', 'flown', 'occurred_at', '2026-03-01T10:00:00Z',
  'origin_id', 897001, 'destination_id', 897002, 'source_checkin_id', 'd0000000-0000-7000-8000-000000000001')));
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000d3', 'role', 'authenticated')::text, true);
select public.sync_checkins(jsonb_build_array(jsonb_build_object(
  'id', 'd0000000-0000-7000-8000-000000000003', 'kind', 'flown', 'occurred_at', '2026-03-01T10:00:00Z',
  'origin_id', 897001, 'destination_id', 897002, 'source_checkin_id', 'd0000000-0000-7000-8000-000000000001')));
select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
select is((select source_checkin_id from public.checkins where id = 'd0000000-0000-7000-8000-000000000002'), 'd0000000-0000-7000-8000-000000000001'::uuid, 'a tagged friend keeps the link to the original');
select is((select source_checkin_id from public.checkins where id = 'd0000000-0000-7000-8000-000000000003'), null, 'someone not tagged does not');

-- A second copy of the same check-in loses the link instead of failing the upload
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000d2', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);
select public.sync_checkins(jsonb_build_array(jsonb_build_object(
  'id', 'd0000000-0000-7000-8000-000000000004', 'kind', 'flown', 'occurred_at', '2026-03-01T10:00:00Z',
  'origin_id', 897001, 'destination_id', 897002, 'source_checkin_id', 'd0000000-0000-7000-8000-000000000001')));
select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
select is((select source_checkin_id from public.checkins where id = 'd0000000-0000-7000-8000-000000000004'), null, 'a check-in can be copied once');
select is((select count(*)::int from public.checkins where id = 'd0000000-0000-7000-8000-000000000004'), 1, 'but the upload still works');

-- Sending the copy again keeps its link
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000d2', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);
select public.sync_checkins(jsonb_build_array(jsonb_build_object(
  'id', 'd0000000-0000-7000-8000-000000000002', 'kind', 'flown', 'occurred_at', '2026-03-01T10:00:00Z',
  'origin_id', 897001, 'destination_id', 897002, 'source_checkin_id', 'd0000000-0000-7000-8000-000000000001')));
select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
select is((select source_checkin_id from public.checkins where id = 'd0000000-0000-7000-8000-000000000002'), 'd0000000-0000-7000-8000-000000000001'::uuid, 'the same upload again keeps the link');

-- Wingman: both people earn it, the one who is neither tagged nor tagging does not
select is((select level from public.user_badges where user_id = '00000000-0000-0000-0000-0000000000d1' and badge_id = 'wingman'), 1, 'the author earns Wingman');
select is((select level from public.user_badges where user_id = '00000000-0000-0000-0000-0000000000d2' and badge_id = 'wingman'), 1, 'so does the tagged friend');
select private.evaluate_badges('00000000-0000-0000-0000-0000000000d3');
select is((select level from public.user_badges where user_id = '00000000-0000-0000-0000-0000000000d3' and badge_id = 'wingman'), null, 'and someone with no tags does not');

select * from finish();
rollback;
