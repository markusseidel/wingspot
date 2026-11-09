-- Milestone 11d: check-ins of one registration, for each relation between viewer and author.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

-- author 1, mutual friend 2, stranger 3, blocked by the author 4
insert into auth.users (id, aud, role, email)
select ('00000000-0000-0000-0000-0000000006' || lpad(n::text, 2, '0'))::uuid, 'authenticated', 'authenticated', 'reg' || n || '@example.test'
from generate_series(1, 4) n;
create function pg_temp.u(n integer) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000006' || lpad(n::text, 2, '0'))::uuid;
$$;
create function pg_temp.as_user(n integer) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true),
         set_config('role', 'authenticated', true);
$$;
create function pg_temp.ids(reg text) returns text language sql as $$
  select coalesce(string_agg(right(id::text, 2), ',' order by occurred_at desc, id desc), '')
  from public.get_registration_checkins(reg)
$$;

insert into public.aircraft_types (icao_code, manufacturer, model) values ('A320', 'Airbus', 'A320');
insert into public.aircraft (id, registration, type_icao, is_sensitive) values
  (651, 'D-AIXY', 'A320', false), (652, 'D-SEXY', 'A320', true), (653, 'D-AIXZ', 'A320', false);
insert into public.follows (follower, followee) values (pg_temp.u(1), pg_temp.u(2)), (pg_temp.u(2), pg_temp.u(1));
insert into public.blocks (blocker, blocked) values (pg_temp.u(1), pg_temp.u(4));

-- 01 public, 02 friends, 03 private, 04 public by the friend, 05 public sensitive by the author, 06 public sensitive by the friend,
-- 07 public other aircraft
insert into public.checkins (id, user_id, kind, occurred_at, visibility, aircraft_id) values
  ('66000000-0000-0000-0000-000000000001', pg_temp.u(1), 'spotted', now() - interval '9 hours', 'public',  651),
  ('66000000-0000-0000-0000-000000000002', pg_temp.u(1), 'spotted', now() - interval '8 hours', 'friends', 651),
  ('66000000-0000-0000-0000-000000000003', pg_temp.u(1), 'spotted', now() - interval '7 hours', 'private', 651),
  ('66000000-0000-0000-0000-000000000004', pg_temp.u(2), 'spotted', now() - interval '6 hours', 'public',  651),
  ('66000000-0000-0000-0000-000000000005', pg_temp.u(1), 'spotted', now() - interval '5 hours', 'public',  652),
  ('66000000-0000-0000-0000-000000000006', pg_temp.u(2), 'spotted', now() - interval '4 hours', 'public',  652),
  ('66000000-0000-0000-0000-000000000007', pg_temp.u(1), 'spotted', now() - interval '3 hours', 'public',  653);

select pg_temp.as_user(1);
select is(pg_temp.ids('D-AIXY'), '04,03,02,01', 'the author sees all of the aircraft''s check-ins, newest first');
select pg_temp.as_user(2);
select is(pg_temp.ids('D-AIXY'), '04,02,01', 'a friend does not see the private one');
select pg_temp.as_user(3);
select is(pg_temp.ids('D-AIXY'), '04,01', 'a stranger sees the public ones');
select pg_temp.as_user(4);
select is(pg_temp.ids('D-AIXY'), '04', 'someone the author blocked sees only the friend''s');

select pg_temp.as_user(1);
select is(pg_temp.ids('daixy'), '04,03,02,01', 'case does not matter');
select is(pg_temp.ids('DAIXY'), '04,03,02,01', 'nor does the hyphen');
select is(pg_temp.ids(' d-aixy '), '04,03,02,01', 'nor spaces');
select is(pg_temp.ids('D-AIXZ'), '07', 'another aircraft has its own list');
select is(pg_temp.ids('D-NONE'), '', 'a registration nobody has seen gives an empty list');

-- sensitive aircraft: only the owner of each check-in sees it
select is(pg_temp.ids('D-SEXY'), '05', 'the author sees only their own check-in of a sensitive aircraft');
select pg_temp.as_user(2);
select is(pg_temp.ids('D-SEXY'), '06', 'the friend sees only theirs, not the author''s');
select pg_temp.as_user(3);
select is(pg_temp.ids('D-SEXY'), '', 'a stranger sees nothing, the same as for an unknown registration');

select pg_temp.as_user(1);
select is((select count(*)::int from public.get_registration_checkins('D-AIXY', page_size => 2)), 2, 'a page holds as many as asked');
select is((select string_agg(right(id::text, 2), ',' order by occurred_at desc, id desc)
           from public.get_registration_checkins('D-AIXY', (select occurred_at from public.checkins where id = '66000000-0000-0000-0000-000000000003'),
                                                 '66000000-0000-0000-0000-000000000003', 2)), '02,01', 'the next page starts after the cursor');
select is((select type_name from public.get_registration_checkins('D-AIXY') limit 1), 'Airbus A320', 'the type name comes along');

select set_config('role', 'anon', true), set_config('request.jwt.claims', '', true);
select throws_ok($$ select * from public.get_registration_checkins('D-AIXY') $$, '42501', null, 'anonymous visitors cannot list check-ins');

select * from finish();
rollback;
