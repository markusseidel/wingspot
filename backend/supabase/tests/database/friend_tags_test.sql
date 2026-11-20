-- Friends on check-ins: who can be tagged, who then sees what, leaving, blocking and unfriending.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

-- a = author, b and c = mutual friends of a, d = only followed by a, e = a friend who switched tags off, f = stranger
insert into auth.users (id, aud, role, email)
select format('00000000-0000-0000-0000-0000000000%s', n)::uuid, 'authenticated', 'authenticated', format('tag%s@example.test', n)
from unnest(array['f1','f2','f3','f4','f5','f6']) n;
insert into public.follows (follower, followee) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000f2'), ('00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-0000000000f1'),
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000f3'), ('00000000-0000-0000-0000-0000000000f3', '00000000-0000-0000-0000-0000000000f1'),
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000f4'),
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000f5'), ('00000000-0000-0000-0000-0000000000f5', '00000000-0000-0000-0000-0000000000f1');
update public.profiles set allow_tags = false where id = '00000000-0000-0000-0000-0000000000f5';
insert into public.airports (id, icao, iata, name, country_code, continent, location) values
  (895001, 'ZZZK', 'ZZK', 'Tag A', 'DE', 'EU', 'POINT(8 50)'), (895002, 'ZZZL', 'ZZL', 'Tag B', 'DE', 'EU', 'POINT(9 51)');

select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000f1', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);
select is((select count(*)::int from public.get_taggable_friends()), 2, 'the picker offers mutual friends who allow tags, not followed-only people or people with tags off');

-- A private flight with five names: friends, a followed-only person, one with tags off, a stranger, and herself
select public.sync_checkins(jsonb_build_array(jsonb_build_object(
  'id', 'f0000000-0000-7000-8000-000000000001', 'kind', 'flown', 'occurred_at', '2026-03-01T10:00:00Z',
  'origin_id', 895001, 'destination_id', 895002, 'visibility', 'private',
  'with', jsonb_build_array('00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-0000000000f3', '00000000-0000-0000-0000-0000000000f4',
                            '00000000-0000-0000-0000-0000000000f5', '00000000-0000-0000-0000-0000000000f6', '00000000-0000-0000-0000-0000000000f1'))));
select is((select count(*)::int from public.checkin_tags where checkin_id = 'f0000000-0000-7000-8000-000000000001'), 2, 'only the two eligible friends are tagged');

-- A tagged friend sees the private check-in and its tags, a stranger does not
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000f2', 'role', 'authenticated')::text, true);
select is((select count(*)::int from public.checkins where id = 'f0000000-0000-7000-8000-000000000001'), 1, 'a tagged friend sees a private check-in');
select is((select count(*)::int from public.get_checkin_tags(array['f0000000-0000-7000-8000-000000000001'::uuid])), 2, 'and its tags');
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000f4', 'role', 'authenticated')::text, true);
select is((select count(*)::int from public.checkins where id = 'f0000000-0000-7000-8000-000000000001'), 0, 'someone not tagged does not see it');
select is((select count(*)::int from public.get_checkin_tags(array['f0000000-0000-7000-8000-000000000001'::uuid])), 0, 'nor its tags');

-- Nobody but the author changes tags through an upload of the same id
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000f3', 'role', 'authenticated')::text, true);
select public.sync_checkins(jsonb_build_array(jsonb_build_object(
  'id', 'f0000000-0000-7000-8000-000000000001', 'kind', 'flown', 'occurred_at', '2026-03-01T10:00:00Z',
  'origin_id', 895001, 'destination_id', 895002, 'with', '[]'::jsonb)));
select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
select is((select count(*)::int from public.checkin_tags where checkin_id = 'f0000000-0000-7000-8000-000000000001'), 2, 'someone else uploading the id changes no tags');

-- Leaving sticks, even when the author sends the list again
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000f3', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);
select public.remove_my_tag('f0000000-0000-7000-8000-000000000001');
select is((select count(*)::int from public.checkins where id = 'f0000000-0000-7000-8000-000000000001'), 0, 'after leaving the check-in is hidden again');
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000f1', 'role', 'authenticated')::text, true);
select public.sync_checkins(jsonb_build_array(jsonb_build_object(
  'id', 'f0000000-0000-7000-8000-000000000001', 'kind', 'flown', 'occurred_at', '2026-03-01T10:00:00Z',
  'origin_id', 895001, 'destination_id', 895002,
  'with', jsonb_build_array('00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-0000000000f3'))));
select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
select is((select array_agg(user_id) from public.checkin_tags where checkin_id = 'f0000000-0000-7000-8000-000000000001'),
          array['00000000-0000-0000-0000-0000000000f2'::uuid], 'a person who left is not added again');

-- Without the key the tags stay; an empty list clears them
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000f1', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);
select public.sync_checkins(jsonb_build_array(jsonb_build_object(
  'id', 'f0000000-0000-7000-8000-000000000001', 'kind', 'flown', 'occurred_at', '2026-03-01T10:00:00Z', 'origin_id', 895001, 'destination_id', 895002)));
select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
select is((select count(*)::int from public.checkin_tags where checkin_id = 'f0000000-0000-7000-8000-000000000001'), 1, 'an upload without the key keeps the tags');

-- Unfriending removes the tags between the two, and with them the access
delete from public.follows where follower = '00000000-0000-0000-0000-0000000000f2' and followee = '00000000-0000-0000-0000-0000000000f1';
select is((select count(*)::int from public.checkin_tags where checkin_id = 'f0000000-0000-7000-8000-000000000001'), 0, 'unfriending removes the tag');

-- More than eight are cut at eight
insert into auth.users (id, aud, role, email)
select format('00000000-0000-0000-0000-00000000a%s', lpad(n::text, 3, '0'))::uuid, 'authenticated', 'authenticated', format('many%s@example.test', n) from generate_series(1, 10) n;
insert into public.follows (follower, followee)
select '00000000-0000-0000-0000-0000000000f1', format('00000000-0000-0000-0000-00000000a%s', lpad(n::text, 3, '0'))::uuid from generate_series(1, 10) n
union all
select format('00000000-0000-0000-0000-00000000a%s', lpad(n::text, 3, '0'))::uuid, '00000000-0000-0000-0000-0000000000f1' from generate_series(1, 10) n;
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000f1', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);
select public.sync_checkins(jsonb_build_array(jsonb_build_object(
  'id', 'f0000000-0000-7000-8000-000000000002', 'kind', 'airport', 'occurred_at', '2026-03-02T10:00:00Z', 'airport_id', 895001, 'context', 'spotting',
  'with', (select jsonb_agg(format('00000000-0000-0000-0000-00000000a%s', lpad(n::text, 3, '0'))) from generate_series(1, 10) n))));
select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
select is((select count(*)::int from public.checkin_tags where checkin_id = 'f0000000-0000-7000-8000-000000000002'), 8, 'a check-in takes at most eight');

-- Blocking removes tags and stops new ones
insert into public.blocks (blocker, blocked) values ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-00000000a001');
select is((select count(*)::int from public.checkin_tags where checkin_id = 'f0000000-0000-7000-8000-000000000002' and user_id = '00000000-0000-0000-0000-00000000a001'), 0, 'blocking removes the tag');

-- Deleting the check-in deletes its tags
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000f1', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);
select public.delete_checkin('f0000000-0000-7000-8000-000000000002');
select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
select is((select count(*)::int from public.checkin_tags where checkin_id = 'f0000000-0000-7000-8000-000000000002'), 0, 'deleting the check-in deletes its tags');

select * from finish();
rollback;
