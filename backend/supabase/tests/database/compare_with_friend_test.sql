-- Compare with a friend: counts and lists, only from what the caller may see.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

-- 1 = me, 2 = a friend (mutual), 3 = a stranger with a private profile
insert into auth.users (id, aud, role, email)
select ('00000000-0000-0000-0000-0000000010' || lpad(n::text, 2, '0'))::uuid, 'authenticated', 'authenticated', 'cmp' || n || '@example.test'
from generate_series(1, 3) n;
create function pg_temp.u(n integer) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000010' || lpad(n::text, 2, '0'))::uuid;
$$;
create function pg_temp.as_user(n integer) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true),
         set_config('role', 'authenticated', true);
$$;
create function pg_temp.reset_role() returns void language sql as $$
  select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
$$;
insert into public.follows (follower, followee) values (pg_temp.u(1), pg_temp.u(2)), (pg_temp.u(2), pg_temp.u(1));
update public.profiles set is_private = true where id = pg_temp.u(3);

insert into public.airports (id, icao, iata, name, country_code, continent, location) values
  (900101, 'ZZ01', 'ZA1', 'Alpha', 'DE', 'EU', 'POINT(8 50)'),
  (900102, 'ZZ02', 'ZA2', 'Beta', 'FR', 'EU', 'POINT(2 48)'),
  (900103, 'ZZ03', 'ZA3', 'Gamma', 'ES', 'EU', 'POINT(-3 40)'),
  (900104, 'ZZ04', 'ZA4', 'Delta', 'IT', 'EU', 'POINT(12 42)');
insert into public.aircraft_types (icao_code, manufacturer, model) values ('ZT1', 'Test', 'One'), ('ZT2', 'Test', 'Two');
insert into public.operators (id, icao, iata, name, country_code) values (900201, 'ZZA', 'ZA', 'Test Air', 'DE'), (900202, 'ZZB', 'ZB', 'Other Air', 'FR');

-- Me: Alpha -> Beta (type 1, Test Air, 500 km) and Beta -> Gamma (type 2, 700 km)
insert into public.checkins (id, user_id, kind, occurred_at, origin_id, destination_id, distance_km, type_icao, operator_id, visibility) values
  ('b1000000-0000-7000-8000-000000000001', pg_temp.u(1), 'flown', '2026-03-01T10:00:00Z', 900101, 900102, 500, 'ZT1', 900201, 'private'),
  ('b1000000-0000-7000-8000-000000000002', pg_temp.u(1), 'flown', '2026-03-02T10:00:00Z', 900102, 900103, 700, 'ZT2', null, 'private');
-- Friend: Alpha -> Beta (type 1, Test Air, 500 km) public, Alpha -> Delta (other air, 900 km) public, and a private flight to Gamma
insert into public.checkins (id, user_id, kind, occurred_at, origin_id, destination_id, distance_km, type_icao, operator_id, visibility) values
  ('b2000000-0000-7000-8000-000000000001', pg_temp.u(2), 'flown', '2026-03-03T10:00:00Z', 900101, 900102, 500, 'ZT1', 900201, 'friends'),
  ('b2000000-0000-7000-8000-000000000002', pg_temp.u(2), 'flown', '2026-03-04T10:00:00Z', 900101, 900104, 900, 'ZT1', 900202, 'public'),
  ('b2000000-0000-7000-8000-000000000003', pg_temp.u(2), 'flown', '2026-03-05T10:00:00Z', 900104, 900103, 1100, 'ZT2', 900202, 'private');

select pg_temp.as_user(1);
select is((select (public.compare_with(pg_temp.u(2)) -> 'me' ->> 'flights')::int), 2, 'my flights');
select is((select (public.compare_with(pg_temp.u(2)) -> 'me' ->> 'distance_km')::int), 1200, 'my distance');
select is((select (public.compare_with(pg_temp.u(2)) -> 'them' ->> 'flights')::int), 2, 'their flights count only what I may see (the private one is left out)');
select is((select (public.compare_with(pg_temp.u(2)) -> 'them' ->> 'distance_km')::int), 1400, 'and their distance');
select is((select (public.compare_with(pg_temp.u(2)) -> 'me' ->> 'airports')::int), 3, 'my airports');
select is((select (public.compare_with(pg_temp.u(2)) -> 'them' ->> 'airports')::int), 3, 'their airports, without the one only a private flight reached');
select is((select (public.compare_with(pg_temp.u(2)) -> 'them' ->> 'countries')::int), 3, 'their countries');

-- Lists
select is((select jsonb_array_length(public.compare_with(pg_temp.u(2)) -> 'airports' -> 'common')), 2, 'two airports in common (Alpha, Beta)');
select is((select public.compare_with(pg_temp.u(2)) -> 'airports' -> 'mine' -> 0 ->> 'code'), 'ZA3', 'Gamma is only mine');
select is((select public.compare_with(pg_temp.u(2)) -> 'airports' -> 'theirs' -> 0 ->> 'code'), 'ZA4', 'Delta is only theirs, Gamma is not shown as theirs');
select is((select jsonb_array_length(public.compare_with(pg_temp.u(2)) -> 'countries' -> 'common')), 2, 'DE and FR in common');
select is((select public.compare_with(pg_temp.u(2)) -> 'airlines' -> 'common' -> 0 ->> 'name'), 'Test Air', 'an airline in common');
select is((select public.compare_with(pg_temp.u(2)) -> 'airlines' -> 'theirs' -> 0 ->> 'name'), 'Other Air', 'an airline only theirs');
select is((select jsonb_array_length(public.compare_with(pg_temp.u(2)) -> 'types' -> 'common')), 1, 'one type in common');
select is((select public.compare_with(pg_temp.u(2)) -> 'types' -> 'mine' -> 0 ->> 'name'), 'Test Two', 'one type only mine (their private flight does not count)');

-- Not available for a private profile of a stranger, or for yourself, or without signing in
select is(public.compare_with(pg_temp.u(3)), null, 'a private profile you do not follow is null');
select is(public.compare_with(pg_temp.u(1)), null, 'yourself is null');
select pg_temp.reset_role();
select set_config('role', 'anon', true);
select throws_ok($$ select public.compare_with('00000000-0000-0000-0000-000000001002') $$, '42501', null, 'anonymous visitors cannot compare');
select pg_temp.reset_role();

select * from finish();
rollback;
