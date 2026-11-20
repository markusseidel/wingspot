-- Badges in the feed: the check-in that earns a badge carries it, and only people who may see that check-in see it.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

-- Hidden badges are not in the repository (see backend/private/README.md), so the test makes its own hidden one.
delete from public.user_badges where badge_id in (select id from public.badges where hidden);
delete from public.badges where hidden;
insert into public.badges (id, name, description, category, kind, rule, levels, hidden, valid_from, position) values
  ('test_hidden_feed', '{"en": "Test hidden"}'::jsonb, '{"en": "Test"}'::jsonb, 'hidden', 'single', '{"metric": "checkins_total"}'::jsonb, '{1}', true, null, 44);

-- a = the author, b = follows a (friend), c = stranger who follows nobody
insert into auth.users (id, aud, role, email)
select format('00000000-0000-0000-0000-0000000000%s', n)::uuid, 'authenticated', 'authenticated', format('feedbadge%s@example.test', n)
from unnest(array['b1','b2','b3']) n;
insert into public.follows (follower, followee) values
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000b2'), ('00000000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-0000000000b1');
insert into public.airports (id, icao, iata, name, country_code, continent, location) values
  (896001, 'ZZZN', 'ZZN', 'Feed badge A', 'DE', 'EU', 'POINT(8 50)');

select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000b1', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);
-- The first check-in earns "Wheels Up" (and the hidden test badge, which must not show)
select public.sync_checkins(jsonb_build_array(
  jsonb_build_object('id', 'b0000000-0000-7000-8000-000000000001', 'kind', 'airport', 'occurred_at', '2026-03-01T10:00:00Z', 'airport_id', 896001, 'context', 'spotting', 'visibility', 'public')));
select is((select string_agg(badge_id, ',' order by badge_id) from public.get_checkin_badges(array['b0000000-0000-7000-8000-000000000001']::uuid[])),
  'wheels_up', 'the check-in shows the badge it earned, and not the hidden one');
select is((select checkin_id from public.user_badges where user_id = '00000000-0000-0000-0000-0000000000b1' and badge_id = 'wheels_up'),
  'b0000000-0000-7000-8000-000000000001'::uuid, 'the badge is tied to that check-in');
select is((select count(*)::int from public.user_badges where user_id = '00000000-0000-0000-0000-0000000000b1' and badge_id = 'test_hidden_feed' and level > 0), 1, 'the hidden badge was earned');

-- A second check-in earns nothing new for Wheels Up: it stays on the first one
select public.sync_checkins(jsonb_build_array(
  jsonb_build_object('id', 'b0000000-0000-7000-8000-000000000002', 'kind', 'airport', 'occurred_at', '2026-03-02T10:00:00Z', 'airport_id', 896001, 'context', 'spotting', 'visibility', 'public')));
select is((select checkin_id from public.user_badges where user_id = '00000000-0000-0000-0000-0000000000b1' and badge_id = 'wheels_up'),
  'b0000000-0000-7000-8000-000000000001'::uuid, 'a later check-in does not take the badge away from the first');

-- A friend sees it, a stranger does not (the check-in is private to a stranger: only friends and followers see it by default)
select set_config('role', 'postgres', true);
update public.checkins set visibility = 'friends' where id = 'b0000000-0000-7000-8000-000000000001';
select set_config('role', 'authenticated', true);
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000b2', 'role', 'authenticated')::text, true);
select is((select count(*)::int from public.get_checkin_badges(array['b0000000-0000-7000-8000-000000000001']::uuid[])), 1, 'a friend sees the badge');
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000b3', 'role', 'authenticated')::text, true);
select is((select count(*)::int from public.get_checkin_badges(array['b0000000-0000-7000-8000-000000000001']::uuid[])), 0, 'a stranger does not');

-- Deleting the check-in takes the badge off it, and nobody errors
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000b1', 'role', 'authenticated')::text, true);
select public.delete_checkin('b0000000-0000-7000-8000-000000000001');
select is((select count(*)::int from public.get_checkin_badges(array['b0000000-0000-7000-8000-000000000001']::uuid[])), 0, 'a deleted check-in shows nothing');

select set_config('role', 'anon', true), set_config('request.jwt.claims', '', true);
select throws_ok($$ select * from public.get_checkin_badges(array[gen_random_uuid()]) $$, '42501', null, 'signed-out clients cannot call it');

select * from finish();
rollback;
