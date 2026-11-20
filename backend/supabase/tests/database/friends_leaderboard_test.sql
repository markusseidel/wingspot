-- Friends leaderboard: opt-in, visibility, ranking.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

-- 1 = me, 2 = followed and opted in, 3 = followed, not opted in, 4 = opted in but not followed, 5 = followed, opted in, blocked
insert into auth.users (id, aud, role, email)
select ('00000000-0000-0000-0000-0000000011' || lpad(n::text, 2, '0'))::uuid, 'authenticated', 'authenticated', 'lb' || n || '@example.test'
from generate_series(1, 5) n;
create function pg_temp.u(n integer) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000011' || lpad(n::text, 2, '0'))::uuid;
$$;
create function pg_temp.as_user(n integer) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true),
         set_config('role', 'authenticated', true);
$$;
create function pg_temp.reset_role() returns void language sql as $$
  select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
$$;
insert into public.follows (follower, followee) values
  (pg_temp.u(1), pg_temp.u(2)), (pg_temp.u(1), pg_temp.u(3)), (pg_temp.u(1), pg_temp.u(5));
update public.profiles set show_on_leaderboard = true where id in (pg_temp.u(2), pg_temp.u(4), pg_temp.u(5));
insert into public.blocks (blocker, blocked) values (pg_temp.u(1), pg_temp.u(5));

insert into public.airports (id, icao, iata, name, country_code, continent, location) values
  (900301, 'ZL01', 'ZL1', 'L Alpha', 'DE', 'EU', 'POINT(8 50)'),
  (900302, 'ZL02', 'ZL2', 'L Beta', 'FR', 'EU', 'POINT(2 48)'),
  (900303, 'ZL03', 'ZL3', 'L Gamma', 'ES', 'EU', 'POINT(-3 40)');
-- me: 500 km this year; 2: 400 km this year (public) + 5000 km two years ago + a private 9000 km this year; 3: 99999 km; 4: 77777 km
insert into public.checkins (id, user_id, kind, occurred_at, origin_id, destination_id, distance_km, visibility) values
  ('c1000000-0000-7000-8000-000000000001', pg_temp.u(1), 'flown', now(), 900301, 900302, 500, 'private'),
  ('c2000000-0000-7000-8000-000000000001', pg_temp.u(2), 'flown', now(), 900301, 900303, 400, 'public'),
  ('c2000000-0000-7000-8000-000000000002', pg_temp.u(2), 'flown', now() - interval '800 days', 900301, 900302, 5000, 'public'),
  ('c2000000-0000-7000-8000-000000000003', pg_temp.u(2), 'flown', now(), 900301, 900302, 9000, 'private'),
  ('c3000000-0000-7000-8000-000000000001', pg_temp.u(3), 'flown', now(), 900301, 900302, 99999, 'public'),
  ('c4000000-0000-7000-8000-000000000001', pg_temp.u(4), 'flown', now(), 900301, 900302, 77777, 'public');

select pg_temp.as_user(1);
select is((select count(*)::int from public.get_leaderboard('distance', 'all')), 2, 'only me and the followed person who opted in (not the others)');
select is((select user_id from public.get_leaderboard('distance', 'all') limit 1), pg_temp.u(2), 'ranked by value, highest first');
select is((select value from public.get_leaderboard('distance', 'all') where user_id = pg_temp.u(2)), 5400::bigint, 'their private flight does not count, the old one does for all time');
select is((select value from public.get_leaderboard('distance', 'year') where user_id = pg_temp.u(2)), 400::bigint, 'and not for this year');
select is((select is_me from public.get_leaderboard('distance', 'year') where user_id = pg_temp.u(1)), true, 'I am marked');
select is((select value from public.get_leaderboard('distance', 'year') where user_id = pg_temp.u(1)), 500::bigint, 'my own private flight counts for me');
select is((select value from public.get_leaderboard('flights', 'all') where user_id = pg_temp.u(2)), 2::bigint, 'flights counted');
select is((select value from public.get_leaderboard('countries', 'all') where user_id = pg_temp.u(2)), 3::bigint, 'countries counted from the airports');
select is((select value from public.get_leaderboard('airports', 'year') where user_id = pg_temp.u(2)), 2::bigint, 'airports counted');
select throws_ok($$ select * from public.get_leaderboard('nonsense', 'all') $$, '22023', null, 'an unknown metric is refused');
select throws_ok($$ select * from public.get_leaderboard('distance', 'decade') $$, '22023', null, 'and an unknown period');

-- Someone who is not opted in sees only themselves
select pg_temp.as_user(3);
select is((select count(*)::int from public.get_leaderboard('distance', 'all')), 1, 'with nobody followed who opted in, only yourself');
select pg_temp.reset_role();
select set_config('role', 'anon', true);
select throws_ok($$ select * from public.get_leaderboard('distance', 'all') $$, '42501', null, 'anonymous visitors cannot read a board');
select pg_temp.reset_role();

select * from finish();
rollback;
