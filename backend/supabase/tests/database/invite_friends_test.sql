-- Invite codes, following by code, and people you may know.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

-- 1 = me, 2 = has a code, 3 and 4 = followed by me, 5 = followed by 3 and 4 (a suggestion), 6 = followed by only 3,
-- 7 = tagged with me, 8 = like 5 but switched suggestions off, 9 = blocked and followed by 3 and 4
insert into auth.users (id, aud, role, email)
select ('00000000-0000-0000-0000-0000000012' || lpad(n::text, 2, '0'))::uuid, 'authenticated', 'authenticated', 'inv' || n || '@example.test'
from generate_series(1, 9) n;
create function pg_temp.u(n integer) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000012' || lpad(n::text, 2, '0'))::uuid;
$$;
create function pg_temp.as_user(n integer) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true),
         set_config('role', 'authenticated', true);
$$;
create function pg_temp.reset_role() returns void language sql as $$
  select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
$$;

-- Codes
select pg_temp.as_user(2);
select is(length(public.get_my_invite_code()), 8, 'a code has 8 characters');
select is(public.get_my_invite_code(), public.get_my_invite_code(), 'and stays the same');
create temp table code2 as select public.get_my_invite_code() as code;
grant select on code2 to public;
select pg_temp.reset_role();

select pg_temp.as_user(1);
select is((select count(*)::int from public.invite_owner((select code from code2))), 1, 'anyone signed in can see who owns a code');
select is((select count(*)::int from public.invite_owner(lower((select code from code2)))), 1, 'in any case');
select is((select count(*)::int from public.invite_owner('NOSUCHCD')), 0, 'an unknown code is nothing');
select throws_ok($$ select invite_code from public.profiles limit 1 $$, '42501', null, 'the codes cannot be read from the table');

-- Following by code
select is((select username from public.follow_by_code((select code from code2))), (select username from public.profiles where id = pg_temp.u(2)), 'following by code answers with the owner');
select pg_temp.reset_role();
select is((select count(*)::int from public.follows where follower = pg_temp.u(1) and followee = pg_temp.u(2)), 1, 'and follows them');
select pg_temp.as_user(1);
select is((select count(*)::int from public.follow_by_code((select code from code2))), 1, 'again is harmless');
select is((select count(*)::int from public.follow_by_code('NOSUCHCD')), 0, 'an unknown code follows nobody');
select pg_temp.reset_role();
select is((select count(*)::int from public.follows where follower = pg_temp.u(1)), 1, 'only one follow exists');

-- A new code ends the old one
select pg_temp.as_user(2);
select public.reset_my_invite_code();
select pg_temp.reset_role();
select pg_temp.as_user(3);
select is((select count(*)::int from public.invite_owner((select code from code2))), 0, 'the old code no longer works');
select pg_temp.reset_role();

-- Suggestions
delete from public.follows;
insert into public.follows (follower, followee) values
  (pg_temp.u(1), pg_temp.u(3)), (pg_temp.u(1), pg_temp.u(4)),
  (pg_temp.u(3), pg_temp.u(5)), (pg_temp.u(4), pg_temp.u(5)),
  (pg_temp.u(3), pg_temp.u(6)),
  (pg_temp.u(3), pg_temp.u(8)), (pg_temp.u(4), pg_temp.u(8)),
  (pg_temp.u(3), pg_temp.u(9)), (pg_temp.u(4), pg_temp.u(9));
update public.profiles set allow_suggestions = false where id = pg_temp.u(8);
insert into public.blocks (blocker, blocked) values (pg_temp.u(1), pg_temp.u(9));
insert into public.airports (id, icao, iata, name, country_code, continent, location) values
  (900401, 'ZI01', 'ZI1', 'Inv A', 'DE', 'EU', 'POINT(8 50)'), (900402, 'ZI02', 'ZI2', 'Inv B', 'FR', 'EU', 'POINT(2 48)');
insert into public.checkins (id, user_id, kind, occurred_at, origin_id, destination_id, visibility) values
  ('d1000000-0000-7000-8000-000000000001', pg_temp.u(1), 'flown', now(), 900401, 900402, 'private');
insert into public.checkin_tags (checkin_id, user_id) values ('d1000000-0000-7000-8000-000000000001', pg_temp.u(7));

select pg_temp.as_user(1);
select is((select array_agg(user_id order by user_id) from public.people_you_may_know()), array[pg_temp.u(5), pg_temp.u(7)], 'followed by two of my follows, or tagged with me; not by only one, not blocked, not switched off');
select is((select reason from public.people_you_may_know() where user_id = pg_temp.u(7)), 'tagged', 'the reason for a tag');
select is((select mutual from public.people_you_may_know() where user_id = pg_temp.u(5)), 2, 'and how many of my follows follow them');
select is((select user_id from public.people_you_may_know() limit 1), pg_temp.u(7), 'tagged people come first');
select pg_temp.reset_role();
select set_config('role', 'anon', true);
select throws_ok($$ select * from public.people_you_may_know() $$, '42501', null, 'anonymous visitors get no suggestions');
select pg_temp.reset_role();

select * from finish();
rollback;
