-- The author is told when a tagged friend adds their flight to their logbook, and can see who did.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

insert into auth.users (id, aud, role, email)
select format('00000000-0000-0000-0000-0000000000%s', n)::uuid, 'authenticated', 'authenticated', format('tcn%s@example.test', n)
from unnest(array['f1','f2','f3']) n;
insert into public.follows (follower, followee) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000f2'), ('00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-0000000000f1'),
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000f3'), ('00000000-0000-0000-0000-0000000000f3', '00000000-0000-0000-0000-0000000000f1');
insert into public.devices (id, user_id, platform, push_token, push_env, app_version, locale)
values ('7f000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000f1', 'ios', 'tcn-token', 'production', '0.2.0', 'en_US');
insert into public.airports (id, icao, iata, name, country_code, continent, location) values
  (899001, 'ZZZT', 'ZZT', 'Copy note A', 'DE', 'EU', 'POINT(8 50)'), (899002, 'ZZZU', 'ZZU', 'Copy note B', 'DE', 'EU', 'POINT(9 51)');

-- f1 tags f2 and f3 on a flight
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000f1', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);
select public.sync_checkins(jsonb_build_array(jsonb_build_object(
  'id', 'f0000000-0000-7000-8000-000000000001', 'kind', 'flown', 'occurred_at', '2026-03-01T10:00:00Z',
  'origin_id', 899001, 'destination_id', 899002,
  'with', jsonb_build_array('00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-0000000000f3'))));
-- f2 adds it to the logbook
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000f2', 'role', 'authenticated')::text, true);
select public.sync_checkins(jsonb_build_array(jsonb_build_object(
  'id', 'f0000000-0000-7000-8000-000000000002', 'kind', 'flown', 'occurred_at', '2026-03-01T10:00:00Z',
  'origin_id', 899001, 'destination_id', 899002, 'source_checkin_id', 'f0000000-0000-7000-8000-000000000001')));
select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);

select is((select count(*)::int from public.notifications where kind = 'tag_copy'), 1, 'one notification for the copy');
select is((select recipient from public.notifications where kind = 'tag_copy'), '00000000-0000-0000-0000-0000000000f1'::uuid, 'to the author');
select is((select actor from public.notifications where kind = 'tag_copy'), '00000000-0000-0000-0000-0000000000f2'::uuid, 'naming who added it');
select is((select checkin_id from public.notifications where kind = 'tag_copy'), 'f0000000-0000-7000-8000-000000000001'::uuid, 'about the original');
select is((select silent from public.notifications where kind = 'tag_copy'), false, 'pushed, as the author has a phone');

-- A copy without a valid link tells nobody (f3 was tagged, but a made-up link is dropped)
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000f3', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);
select public.sync_checkins(jsonb_build_array(jsonb_build_object(
  'id', 'f0000000-0000-7000-8000-000000000003', 'kind', 'flown', 'occurred_at', '2026-03-01T10:00:00Z',
  'origin_id', 899001, 'destination_id', 899002)));
select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
select is((select count(*)::int from public.notifications where kind = 'tag_copy'), 1, 'a flight added without the link tells nobody');

-- Who copied: only the author sees it
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000f1', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);
select is((select count(*)::int from public.get_checkin_copies('f0000000-0000-7000-8000-000000000001')), 1, 'the author sees who added it');
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000f3', 'role', 'authenticated')::text, true);
select is((select count(*)::int from public.get_checkin_copies('f0000000-0000-7000-8000-000000000001')), 0, 'nobody else does');
select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
insert into public.blocks (blocker, blocked) values ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000f2');
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000f1', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);
select is((select count(*)::int from public.get_checkin_copies('f0000000-0000-7000-8000-000000000001')), 0, 'a blocked person is left out');
select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);

select * from finish();
rollback;
