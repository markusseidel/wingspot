-- The Followers sharing level: followers see it without a follow back, and are alerted.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

-- 1 is the author. 2 only follows 1. 3 follows nobody. 4 is a friend of 1.
insert into auth.users (id, aud, role, email)
select ('00000000-0000-0000-0000-0000000009' || lpad(n::text, 2, '0'))::uuid, 'authenticated', 'authenticated', 'followers' || n || '@example.test'
from generate_series(1, 4) n;
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
insert into public.aircraft_types (icao_code, manufacturer, model) values ('A321', 'Airbus', 'A321');
insert into public.aircraft (id, registration, type_icao, is_sensitive) values (891, 'D-AIFO', 'A321', false);
insert into public.follows (follower, followee) values
  (pg_temp.u(2), pg_temp.u(1)), (pg_temp.u(4), pg_temp.u(1)), (pg_temp.u(1), pg_temp.u(4));
insert into public.devices (id, user_id, platform, push_token, push_env, app_version, locale)
values ('89000000-0000-0000-0000-000000000002', pg_temp.u(2), 'ios', 'follower-token', 'production', '0.2.0', 'en_US');
insert into public.notification_rules (watcher, target, spotted) values (pg_temp.u(2), pg_temp.u(1), true);
update public.profiles set is_private = false where id = pg_temp.u(1);

insert into public.checkins (id, user_id, kind, occurred_at, visibility, aircraft_id)
values ('89000000-0000-0000-0000-0000000000c1', pg_temp.u(1), 'spotted', now(), 'followers', 891);

select is((select count(*)::int from public.notifications where recipient = pg_temp.u(2) and kind = 'checkin'), 1,
          'a follower with an alert is told about a followers check-in, without following back');

select pg_temp.as_user(2);
select is((select count(*)::int from public.checkins where id = '89000000-0000-0000-0000-0000000000c1'), 1, 'a follower sees it');
select pg_temp.as_user(3);
select is((select count(*)::int from public.checkins where id = '89000000-0000-0000-0000-0000000000c1'), 0, 'a stranger does not');
select pg_temp.as_user(4);
select is((select count(*)::int from public.checkins where id = '89000000-0000-0000-0000-0000000000c1'), 1, 'a friend does');

-- A private profile still shows check-ins only to friends.
select pg_temp.reset_role();
update public.profiles set is_private = true where id = pg_temp.u(1);
select pg_temp.as_user(2);
select is((select count(*)::int from public.checkins where id = '89000000-0000-0000-0000-0000000000c1'), 0, 'a private profile hides it from a plain follower');
select pg_temp.as_user(4);
select is((select count(*)::int from public.checkins where id = '89000000-0000-0000-0000-0000000000c1'), 1, 'but not from a friend');

-- The level can be chosen as the default, and is accepted when syncing
select pg_temp.as_user(1);
select lives_ok($$ select public.set_sharing('followers', false) $$, 'followers is a valid sharing choice');
select pg_temp.reset_role();
select is((select default_visibility from public.profiles where id = pg_temp.u(1)), 'followers', 'and is stored');
select pg_temp.as_user(1);
select is((public.sync_checkins(jsonb_build_array(jsonb_build_object(
  'id', gen_random_uuid(), 'kind', 'spotted', 'occurred_at', now(), 'type_icao', 'A321', 'visibility', 'followers')))
  -> 'results' -> 0 ->> 'status'), 'stored', 'a followers check-in is accepted by the sync');
select pg_temp.reset_role();

select * from finish();
rollback;
