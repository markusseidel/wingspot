-- Milestone 11b: busy airports, for each relation between viewer and author.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

-- author 1, mutual friend 2, stranger 3, blocked by the author 4
insert into auth.users (id, aud, role, email)
select ('00000000-0000-0000-0000-0000000006' || lpad(n::text, 2, '0'))::uuid, 'authenticated', 'authenticated', 'busy' || n || '@example.test'
from generate_series(1, 4) n;
create function pg_temp.u(n integer) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000006' || lpad(n::text, 2, '0'))::uuid;
$$;
create function pg_temp.as_user(n integer) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true),
         set_config('role', 'authenticated', true);
$$;
create function pg_temp.codes() returns text language sql as $$
  select coalesce(string_agg(airport_code || ':' || checkins, ',' order by checkins desc, airport_name), '')
  from public.get_active_airports(7, 10)
$$;

insert into public.airports (id, icao, iata, name, country_code, continent, location) values
  (6601, 'EDXA', 'XAA', 'Alpha Airport', 'DE', 'EU', 'POINT(8 50)'),
  (6602, 'EDXB', 'XAB', 'Beta Airport', 'DE', 'EU', 'POINT(9 51)'),
  (6603, 'EDXC', null, 'Gamma Field', 'DE', 'EU', 'POINT(10 52)');
insert into public.aircraft_types (icao_code, manufacturer, model) values ('A320', 'Airbus', 'A320');
insert into public.aircraft (id, registration, type_icao, is_sensitive) values
  (661, 'D-AIBA', 'A320', false), (662, 'D-SEBA', 'A320', true);
insert into public.follows (follower, followee) values (pg_temp.u(1), pg_temp.u(2)), (pg_temp.u(2), pg_temp.u(1));
insert into public.blocks (blocker, blocked) values (pg_temp.u(1), pg_temp.u(4));

-- Alpha: 1 public, 2 friends, 3 private, 4 public with a sensitive aircraft, 5 public visit, 6 public 10 days ago
-- Beta: 7 public, 8 public by the friend; Gamma (no IATA code): 9 public; a flight from Alpha: 10
insert into public.checkins (id, user_id, kind, occurred_at, visibility, aircraft_id, airport_id, origin_id, destination_id) values
  ('66000000-0000-0000-0000-000000000001', pg_temp.u(1), 'spotted', now() - interval '6 hours', 'public',  661, 6601, null, null),
  ('66000000-0000-0000-0000-000000000002', pg_temp.u(1), 'spotted', now() - interval '5 hours', 'friends', 661, 6601, null, null),
  ('66000000-0000-0000-0000-000000000003', pg_temp.u(1), 'spotted', now() - interval '4 hours', 'private', 661, 6601, null, null),
  ('66000000-0000-0000-0000-000000000004', pg_temp.u(1), 'spotted', now() - interval '3 hours', 'public',  662, 6601, null, null),
  ('66000000-0000-0000-0000-000000000005', pg_temp.u(1), 'airport', now() - interval '2 hours', 'public',  null, 6601, null, null),
  ('66000000-0000-0000-0000-000000000006', pg_temp.u(1), 'spotted', now() - interval '10 days', 'public', 661, 6601, null, null),
  ('66000000-0000-0000-0000-000000000007', pg_temp.u(1), 'spotted', now() - interval '6 hours', 'public',  661, 6602, null, null),
  ('66000000-0000-0000-0000-000000000008', pg_temp.u(2), 'airport', now() - interval '6 hours', 'public',  null, 6602, null, null),
  ('66000000-0000-0000-0000-000000000009', pg_temp.u(2), 'airport', now() - interval '1 hours', 'public',  null, 6603, null, null),
  ('66000000-0000-0000-0000-000000000010', pg_temp.u(1), 'flown',   now() - interval '1 hours', 'public',  661, null, 6601, 6602);

select pg_temp.as_user(1);
select is(pg_temp.codes(), 'XAA:5,XAB:2,EDXC:1', 'the author counts all their own, without flights and the old one, and an airport without an IATA code shows its ICAO code');
select pg_temp.as_user(2);
select is(pg_temp.codes(), 'XAA:3,XAB:2,EDXC:1', 'a friend counts public and friends-only, not private, and not the sensitive aircraft');
select pg_temp.as_user(3);
select is(pg_temp.codes(), 'XAA:2,XAB:2,EDXC:1', 'a stranger counts the public ones only, without the sensitive aircraft');
select pg_temp.as_user(4);
select is(pg_temp.codes(), 'XAB:1,EDXC:1', 'someone the author blocked counts only the friend''s check-ins');

select pg_temp.as_user(3);
select is((select people from public.get_active_airports(7, 10) where airport_id = 6602), 2, 'people are the different authors');
select is((select count(*)::int from public.get_active_airports(30, 10) where airport_id = 6601 and checkins = 3), 1, 'a longer period counts the older check-in too');
select is((select count(*)::int from public.get_active_airports(7, 1)), 1, 'the list is as long as asked');
select is((select airport_code from public.get_active_airports(7, 1)), 'XAA', 'and the busiest comes first');

select set_config('role', 'anon', true), set_config('request.jwt.claims', '', true);
select throws_ok($$ select * from public.get_active_airports() $$, '42501', null, 'anonymous visitors cannot call it');

select * from finish();
rollback;
