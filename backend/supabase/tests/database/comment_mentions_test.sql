-- Mentions and salutes on comments.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

-- 1 owns a friends-only check-in, 2 comments, 3 is a mutual friend of both, 4 only follows 2, 5 is a friend of 2 but
-- not of 1 (so cannot see the check-in), 6 is blocked by 2
insert into auth.users (id, aud, role, email)
select ('00000000-0000-0000-0000-0000000009' || lpad(n::text, 2, '0'))::uuid, 'authenticated', 'authenticated', 'cmt' || n || '@example.test'
from generate_series(1, 6) n;
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
update public.profiles set username = 'cm_' || right(id::text, 2) where id::text like '00000000-0000-0000-0000-0000000009%';
-- usernames are cm_01 .. cm_06
insert into public.follows (follower, followee) values
  (pg_temp.u(1), pg_temp.u(2)), (pg_temp.u(2), pg_temp.u(1)),
  (pg_temp.u(1), pg_temp.u(3)), (pg_temp.u(3), pg_temp.u(1)),
  (pg_temp.u(2), pg_temp.u(3)), (pg_temp.u(3), pg_temp.u(2)),
  (pg_temp.u(4), pg_temp.u(2)),
  (pg_temp.u(2), pg_temp.u(5)), (pg_temp.u(5), pg_temp.u(2)),
  (pg_temp.u(2), pg_temp.u(6)), (pg_temp.u(6), pg_temp.u(2));
insert into public.blocks (blocker, blocked) values (pg_temp.u(2), pg_temp.u(6));
insert into public.devices (id, user_id, platform, push_token, push_env, app_version, locale)
values ('99000000-0000-0000-0000-000000000003', pg_temp.u(3), 'ios', 'cm-token-3', 'production', '0.2.0', 'en_US');
insert into public.airports (id, icao, iata, name, country_code, continent, location) values
  (898001, 'ZZZR', 'ZZR', 'Mention A', 'DE', 'EU', 'POINT(8 50)'), (898002, 'ZZZS', 'ZZS', 'Mention B', 'DE', 'EU', 'POINT(9 51)');
insert into public.checkins (id, user_id, kind, occurred_at, origin_id, destination_id, visibility) values
  ('a9000000-0000-7000-8000-000000000001', pg_temp.u(1), 'flown', '2026-03-01T10:00:00Z', 898001, 898002, 'friends');

-- A comment with several @names. Only the friend who may see the check-in is kept.
insert into public.comments (id, checkin_id, user_id, body) values
  ('c9000000-0000-7000-8000-000000000001', 'a9000000-0000-7000-8000-000000000001', pg_temp.u(2),
   'Hi @CM_03, and @cm_04 and @cm_05 and @cm_06, also @cm_02 and mail@cm_01.test and @nobody_here');
select is((select array_agg(user_id order by user_id) from public.comment_mentions where comment_id = 'c9000000-0000-7000-8000-000000000001'),
  array[pg_temp.u(3)], 'only a mutual friend who may see the check-in is mentioned');
select is((select count(*)::int from public.notifications where kind = 'mention'), 1, 'one notification for it');
select is((select recipient from public.notifications where kind = 'mention'), pg_temp.u(3), 'to the mentioned person');
select is((select snippet from public.notifications where kind = 'mention'), left('Hi @CM_03, and @cm_04 and @cm_05 and @cm_06, also @cm_02 and mail@cm_01.test and @nobody_here', 80), 'with the start of the comment');
select is((select silent from public.notifications where kind = 'mention'), false, 'and it is pushed, as they have a phone');

-- A reply that starts with the name is a mention too (the author of the first comment is the check-in owner here)
insert into public.comments (id, checkin_id, user_id, body) values
  ('c9000000-0000-7000-8000-000000000002', 'a9000000-0000-7000-8000-000000000001', pg_temp.u(3), '@cm_02 thanks!');
select is((select user_id from public.comment_mentions where comment_id = 'c9000000-0000-7000-8000-000000000002'), pg_temp.u(2), 'a reply mentions the person it answers');

-- Not readable directly
select pg_temp.as_user(3);
select throws_ok($$ select * from public.comment_mentions $$, '42501', null, 'the mention table cannot be read directly');
select throws_ok($$ select * from public.comment_salutes $$, '42501', null, 'nor the salutes');

-- Extras
select is((select mentions -> 0 ->> 'username' from public.get_comment_extras('a9000000-0000-7000-8000-000000000001') where comment_id = 'c9000000-0000-7000-8000-000000000001'),
  'cm_03', 'the extras name who is mentioned');
select is((select count(*)::int from public.get_comment_extras('a9000000-0000-7000-8000-000000000001')), 2, 'for each comment');
select pg_temp.as_user(5);
select is((select count(*)::int from public.get_comment_extras('a9000000-0000-7000-8000-000000000001')), 0, 'and nothing for someone who may not see the check-in');
select pg_temp.reset_role();

-- Salutes on comments
select pg_temp.as_user(3);
select public.set_comment_salute('c9000000-0000-7000-8000-000000000001', true);
select public.set_comment_salute('c9000000-0000-7000-8000-000000000001', true);
select is((select salutes from public.get_comment_extras('a9000000-0000-7000-8000-000000000001') where comment_id = 'c9000000-0000-7000-8000-000000000001'), 1, 'a comment salute counts once');
select is((select saluted from public.get_comment_extras('a9000000-0000-7000-8000-000000000001') where comment_id = 'c9000000-0000-7000-8000-000000000001'), true, 'and says it is yours');
select pg_temp.reset_role();
select is((select count(*)::int from public.notifications where kind = 'comment_like' and recipient = pg_temp.u(2)), 1, 'the author is told once');
select pg_temp.as_user(1);
select is((select saluted from public.get_comment_extras('a9000000-0000-7000-8000-000000000001') where comment_id = 'c9000000-0000-7000-8000-000000000001'), false, 'it is not yours for someone else');
select pg_temp.as_user(5);
select public.set_comment_salute('c9000000-0000-7000-8000-000000000001', true);
select pg_temp.reset_role();
select is((select count(*)::int from public.comment_salutes), 1, 'someone who may not see the check-in cannot salute');
select pg_temp.as_user(3);
select public.set_comment_salute('c9000000-0000-7000-8000-000000000001', false);
select is((select salutes from public.get_comment_extras('a9000000-0000-7000-8000-000000000001') where comment_id = 'c9000000-0000-7000-8000-000000000001'), 0, 'a salute can be taken back');
select pg_temp.reset_role();

-- Deleting the comment removes its mentions and salutes
delete from public.comments where id = 'c9000000-0000-7000-8000-000000000001';
select is((select count(*)::int from public.comment_mentions where comment_id = 'c9000000-0000-7000-8000-000000000001'), 0, 'deleting a comment removes its mentions');

-- Not callable without signing in
select set_config('role', 'anon', true);
select throws_ok($$ select public.set_comment_salute('c9000000-0000-7000-8000-000000000002', true) $$, '42501', null, 'anonymous visitors cannot salute');
select pg_temp.reset_role();

select * from finish();
rollback;
