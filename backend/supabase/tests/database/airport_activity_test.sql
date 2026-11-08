-- Milestone 8e: check-ins and counts at one airport, for each relation between viewer and author.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

-- author 1, mutual friend 2, stranger 3, blocked by the author 4
insert into auth.users (id, aud, role, email)
select ('00000000-0000-0000-0000-0000000008' || lpad(n::text, 2, '0'))::uuid, 'authenticated', 'authenticated', 'airport' || n || '@example.test'
from generate_series(1, 4) n;

create function pg_temp.as_user(n integer) returns void language sql as $$
  select set_config('request.jwt.claims',
           json_build_object('sub', '00000000-0000-0000-0000-0000000008' || lpad(n::text, 2, '0'), 'role', 'authenticated')::text, true),
         set_config('role', 'authenticated', true);
$$;
create function pg_temp.u(n integer) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000008' || lpad(n::text, 2, '0'))::uuid;
$$;
create function pg_temp.ids(n integer) returns text language sql as $$
  select coalesce(string_agg(right(id::text, 1), ',' order by occurred_at desc, id desc), '')
  from public.get_airport_checkins(8801) $$;

insert into public.airports (id, icao, iata, name, country_code, continent, location) values
  (8801, 'EDXA', 'XAA', 'Test Airport A', 'DE', 'EU', 'POINT(8 50)'),
  (8802, 'EDXB', 'XAB', 'Test Airport B', 'DE', 'EU', 'POINT(9 51)');
insert into public.aircraft_types (icao_code, manufacturer, model) values ('A320', 'Airbus', 'A320');
insert into public.aircraft (id, registration, type_icao, is_sensitive) values
  (881, 'D-AIXA', 'A320', false), (882, 'D-SEXA', 'A320', true), (883, 'D-AIXB', 'A320', false);

insert into public.follows (follower, followee) values (pg_temp.u(1), pg_temp.u(2)), (pg_temp.u(2), pg_temp.u(1));
insert into public.blocks (blocker, blocked) values (pg_temp.u(1), pg_temp.u(4));

-- at A: 1 public spotted, 2 friends-only, 3 private, 4 public sensitive aircraft, 5 public airport visit,
-- 6 public but 40 days ago; at B: 7; a public flight from A: 8
insert into public.checkins (id, user_id, kind, occurred_at, visibility, aircraft_id, airport_id, origin_id, destination_id) values
  ('88000000-0000-0000-0000-000000000001', pg_temp.u(1), 'spotted', now() - interval '6 hours', 'public',  881, 8801, null, null),
  ('88000000-0000-0000-0000-000000000002', pg_temp.u(1), 'spotted', now() - interval '5 hours', 'friends', 881, 8801, null, null),
  ('88000000-0000-0000-0000-000000000003', pg_temp.u(1), 'spotted', now() - interval '4 hours', 'private', 883, 8801, null, null),
  ('88000000-0000-0000-0000-000000000004', pg_temp.u(1), 'spotted', now() - interval '3 hours', 'public',  882, 8801, null, null),
  ('88000000-0000-0000-0000-000000000005', pg_temp.u(1), 'airport', now() - interval '2 hours', 'public',  null, 8801, null, null),
  ('88000000-0000-0000-0000-000000000006', pg_temp.u(1), 'spotted', now() - interval '40 days', 'public', 881, 8801, null, null),
  ('88000000-0000-0000-0000-000000000007', pg_temp.u(1), 'spotted', now() - interval '6 hours', 'public',  881, 8802, null, null),
  ('88000000-0000-0000-0000-000000000008', pg_temp.u(1), 'flown',   now() - interval '1 hours', 'public',  881, null, 8801, 8802);

select pg_temp.as_user(1);
select is(pg_temp.ids(1), '5,4,3,2,1,6', 'the author sees all of their check-ins at the airport, newest first, without flights');
select pg_temp.as_user(2);
select is(pg_temp.ids(2), '5,4,2,1,6', 'a friend sees public and friends-only, but not private');
select pg_temp.as_user(3);
select is(pg_temp.ids(3), '5,4,1,6', 'a stranger sees the public ones');
select pg_temp.as_user(4);
select is(pg_temp.ids(4), '', 'someone the author blocked sees nothing');

select pg_temp.as_user(3);
select is((select registration from public.get_airport_checkins(8801) where id = '88000000-0000-0000-0000-000000000004'), null::text,
          'the registration of a sensitive aircraft is hidden from others');
select pg_temp.as_user(1);
select is((select registration from public.get_airport_checkins(8801) where id = '88000000-0000-0000-0000-000000000004'), 'D-SEXA',
          'but not from its owner');
select is((select count(*)::int from public.get_airport_checkins(8801, page_size => 2)), 2, 'a page holds as many as asked');
select is((select string_agg(right(id::text, 1), ',' order by occurred_at desc, id desc)
           from public.get_airport_checkins(8801, (select occurred_at from public.checkins where id = '88000000-0000-0000-0000-000000000004'),
                                            '88000000-0000-0000-0000-000000000004', 2)), '3,2', 'the next page starts after the cursor');
select is((select count(*)::int from public.get_airport_checkins(8802)), 1, 'another airport has its own list');

-- Counts: last 30 days only
select pg_temp.as_user(1);
select is((select checkins_30d from public.get_airport_activity(8801)), 5, 'the author counts all five recent check-ins');
select is((select aircraft_30d from public.get_airport_activity(8801)), 3, 'and all three different aircraft');
select pg_temp.as_user(3);
select is((select checkins_30d from public.get_airport_activity(8801)), 3, 'a stranger counts the public ones');
select is((select aircraft_30d from public.get_airport_activity(8801)), 1, 'and does not count the sensitive aircraft');
select is((select top_spotters->0->>'username' from public.get_airport_activity(8801)),
          (select username from public.profiles where id = pg_temp.u(1)), 'the top spotter is the author');
select is((select (top_spotters->0->>'checkins')::int from public.get_airport_activity(8801)), 3, 'with the number of visible check-ins');
select pg_temp.as_user(4);
select is((select checkins_30d from public.get_airport_activity(8801)), 0, 'a blocked viewer counts nothing');
select is((select top_spotters from public.get_airport_activity(8801)), '[]'::jsonb, 'and sees no spotters');

select set_config('role', 'anon', true), set_config('request.jwt.claims', '', true);
select throws_ok($$ select * from public.get_airport_checkins(8801) $$, '42501', null, 'anonymous visitors cannot list check-ins');
select throws_ok($$ select * from public.get_airport_activity(8801) $$, '42501', null, 'or read the counts');

select * from finish();
rollback;
