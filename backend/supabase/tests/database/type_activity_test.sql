-- Milestone 11c: check-ins and counts for one aircraft type, for each relation between viewer and author.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

-- author 1, mutual friend 2, stranger 3, blocked by the author 4
insert into auth.users (id, aud, role, email)
select ('00000000-0000-0000-0000-0000000005' || lpad(n::text, 2, '0'))::uuid, 'authenticated', 'authenticated', 'type' || n || '@example.test'
from generate_series(1, 4) n;
create function pg_temp.u(n integer) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000005' || lpad(n::text, 2, '0'))::uuid;
$$;
create function pg_temp.as_user(n integer) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true),
         set_config('role', 'authenticated', true);
$$;
create function pg_temp.ids() returns text language sql as $$
  select coalesce(string_agg(right(id::text, 2), ',' order by occurred_at desc, id desc), '')
  from public.get_type_checkins('a320')
$$;

insert into public.aircraft_types (icao_code, manufacturer, model) values ('A320', 'Airbus', 'A320'), ('B738', 'Boeing', '737-800');
insert into public.aircraft (id, registration, type_icao, is_sensitive) values
  (551, 'D-AIXA', 'A320', false), (552, 'D-SEXA', 'A320', true), (553, 'D-AIXB', 'B738', false);
insert into public.airports (id, icao, iata, name, country_code, continent, location) values
  (5501, 'EDXD', 'XDA', 'Delta Airport', 'DE', 'EU', 'POINT(8 50)'),
  (5502, 'EDXE', 'XDB', 'Echo Airport', 'DE', 'EU', 'POINT(9 51)');
insert into public.follows (follower, followee) values (pg_temp.u(1), pg_temp.u(2)), (pg_temp.u(2), pg_temp.u(1));
insert into public.blocks (blocker, blocked) values (pg_temp.u(1), pg_temp.u(4));

-- 01 public A320, 02 friends A320, 03 private A320, 04 public sensitive A320, 05 public A320 by type only (no aircraft),
-- 06 public A320 40 days ago, 07 public B738, 08 public A320 flight, 09 public A320 by the friend at another airport
insert into public.checkins (id, user_id, kind, occurred_at, visibility, aircraft_id, type_icao, airport_id, origin_id, destination_id) values
  ('55000000-0000-0000-0000-000000000001', pg_temp.u(1), 'spotted', now() - interval '9 hours', 'public',  551, null, 5501, null, null),
  ('55000000-0000-0000-0000-000000000002', pg_temp.u(1), 'spotted', now() - interval '8 hours', 'friends', 551, null, 5501, null, null),
  ('55000000-0000-0000-0000-000000000003', pg_temp.u(1), 'spotted', now() - interval '7 hours', 'private', 551, null, 5501, null, null),
  ('55000000-0000-0000-0000-000000000004', pg_temp.u(1), 'spotted', now() - interval '6 hours', 'public',  552, null, 5501, null, null),
  ('55000000-0000-0000-0000-000000000005', pg_temp.u(1), 'spotted', now() - interval '5 hours', 'public', null, 'A320', 5501, null, null),
  ('55000000-0000-0000-0000-000000000006', pg_temp.u(1), 'spotted', now() - interval '40 days', 'public', 551, null, 5501, null, null),
  ('55000000-0000-0000-0000-000000000007', pg_temp.u(1), 'spotted', now() - interval '4 hours', 'public',  553, null, 5501, null, null),
  ('55000000-0000-0000-0000-000000000008', pg_temp.u(1), 'flown',   now() - interval '3 hours', 'public',  551, null, null, 5501, 5502),
  ('55000000-0000-0000-0000-000000000009', pg_temp.u(2), 'spotted', now() - interval '2 hours', 'public',  551, null, 5502, null, null);

select pg_temp.as_user(1);
select is(pg_temp.ids(), '09,08,05,04,03,02,01,06', 'the author sees all check-ins of the type, newest first, matched by type or aircraft, and not the Boeing');
select pg_temp.as_user(2);
select is(pg_temp.ids(), '09,08,05,04,02,01,06', 'a friend sees public and friends-only, but not private');
select pg_temp.as_user(3);
select is(pg_temp.ids(), '09,08,05,04,01,06', 'a stranger sees the public ones');
select pg_temp.as_user(4);
select is(pg_temp.ids(), '09', 'someone the author blocked sees only the friend''s');

select pg_temp.as_user(3);
select is((select registration from public.get_type_checkins('A320') where id = '55000000-0000-0000-0000-000000000004'), null::text,
          'the registration of a sensitive aircraft is hidden from others');
select is((select type_name from public.get_type_checkins('A320') where id = '55000000-0000-0000-0000-000000000005'), 'Airbus A320', 'the type name comes along');
select pg_temp.as_user(1);
select is((select registration from public.get_type_checkins('A320') where id = '55000000-0000-0000-0000-000000000004'), 'D-SEXA', 'but not from its owner');
select is((select count(*)::int from public.get_type_checkins('a320', page_size => 2)), 2, 'a page holds as many as asked, and the code may be lower case');
select is((select string_agg(right(id::text, 2), ',' order by occurred_at desc, id desc)
           from public.get_type_checkins('A320', (select occurred_at from public.checkins where id = '55000000-0000-0000-0000-000000000005'),
                                         '55000000-0000-0000-0000-000000000005', 2)), '04,03', 'the next page starts after the cursor');
select is((select count(*)::int from public.get_type_checkins('B738')), 1, 'another type has its own list');
select is((select count(*)::int from public.get_type_checkins('ZZZZ')), 0, 'an unknown type gives an empty list');

-- Counts: last 30 days, without the sensitive aircraft of others
select pg_temp.as_user(1);
select is((select checkins_30d from public.get_type_activity('A320')), 7, 'the author counts 7 recent check-ins, with the friend''s');
select is((select airports_30d from public.get_type_activity('A320')), 2, 'at two airports');
select pg_temp.as_user(3);
select is((select checkins_30d from public.get_type_activity('A320')), 4, 'a stranger counts the public ones without the sensitive aircraft');
select is((select top_spotters->0->>'username' from public.get_type_activity('A320')),
          (select username from public.profiles where id = pg_temp.u(1)), 'the top spotter is the author');
select is((select (top_spotters->0->>'checkins')::int from public.get_type_activity('A320')), 3, 'with the number of visible check-ins');
select pg_temp.as_user(4);
select is((select checkins_30d from public.get_type_activity('A320')), 1, 'a blocked viewer counts only what the friend shared');

select set_config('role', 'anon', true), set_config('request.jwt.claims', '', true);
select throws_ok($$ select * from public.get_type_checkins('A320') $$, '42501', null, 'anonymous visitors cannot list check-ins');
select throws_ok($$ select * from public.get_type_activity('A320') $$, '42501', null, 'or read the counts');

select * from finish();
rollback;
