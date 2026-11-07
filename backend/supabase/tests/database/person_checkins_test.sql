-- Milestone 8d: one person's check-ins, for each relation between viewer and author.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

-- author 1, mutual friend 2, one-way follower 3, stranger 4, blocked by the author 5
insert into auth.users (id, aud, role, email)
select ('00000000-0000-0000-0000-0000000009' || lpad(n::text, 2, '0'))::uuid, 'authenticated', 'authenticated',
       'person' || n || '@example.test'
from generate_series(1, 5) n;

create function pg_temp.as_user(n integer) returns void language sql as $$
  select set_config('request.jwt.claims',
           json_build_object('sub', '00000000-0000-0000-0000-0000000009' || lpad(n::text, 2, '0'), 'role', 'authenticated')::text, true),
         set_config('role', 'authenticated', true);
$$;
create function pg_temp.u(n integer) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000009' || lpad(n::text, 2, '0'))::uuid;
$$;
create function pg_temp.ids(n integer) returns text language sql as $$
  select coalesce(string_agg(right(id::text, 1), ',' order by occurred_at desc, id desc), '')
  from public.get_person_checkins(pg_temp.u(1)) $$;

insert into public.aircraft_types (icao_code, manufacturer, model) values ('A320', 'Airbus', 'A320');
insert into public.aircraft (id, registration, type_icao, is_sensitive) values
  (931, 'D-AIPC', 'A320', false), (932, 'D-SEPC', 'A320', true);

insert into public.follows (follower, followee) values
  (pg_temp.u(1), pg_temp.u(2)), (pg_temp.u(2), pg_temp.u(1)), (pg_temp.u(3), pg_temp.u(1)), (pg_temp.u(5), pg_temp.u(1));
insert into public.blocks (blocker, blocked) values (pg_temp.u(1), pg_temp.u(5));

-- 1: public, 2: friends, 3: private, 4: public with a sensitive aircraft, 5: public but 10 minutes ago
insert into public.checkins (id, user_id, kind, occurred_at, visibility, aircraft_id) values
  ('91000000-0000-0000-0000-000000000001', pg_temp.u(1), 'spotted', now() - interval '5 hours', 'public',  931),
  ('91000000-0000-0000-0000-000000000002', pg_temp.u(1), 'spotted', now() - interval '4 hours', 'friends', 931),
  ('91000000-0000-0000-0000-000000000003', pg_temp.u(1), 'spotted', now() - interval '3 hours', 'private', 931),
  ('91000000-0000-0000-0000-000000000004', pg_temp.u(1), 'spotted', now() - interval '2 hours', 'public',  932),
  ('91000000-0000-0000-0000-000000000005', pg_temp.u(1), 'spotted', now() - interval '10 minutes', 'public', 931);
update public.profiles set post_delay_minutes = 60 where id = pg_temp.u(1);
insert into public.salutes (user_id, checkin_id) values (pg_temp.u(2), '91000000-0000-0000-0000-000000000001');
insert into public.comments (checkin_id, user_id, body) values ('91000000-0000-0000-0000-000000000001', pg_temp.u(2), 'nice');

select pg_temp.as_user(1);
select is(pg_temp.ids(1), '5,4,3,2,1', 'the author sees everything, newest first');
select pg_temp.as_user(2);
select is(pg_temp.ids(2), '5,4,2,1', 'a mutual friend sees public and friends-only, also inside the delay, but not private');
select pg_temp.as_user(3);
select is(pg_temp.ids(3), '4,1', 'a one-way follower sees only older public check-ins');
select pg_temp.as_user(4);
select is(pg_temp.ids(4), '4,1', 'a stranger sees the same');
select pg_temp.as_user(5);
select is(pg_temp.ids(5), '', 'someone the author blocked sees nothing');

select pg_temp.as_user(4);
select is((select registration from public.get_person_checkins(pg_temp.u(1)) where id = '91000000-0000-0000-0000-000000000004'), null::text,
          'the registration of a sensitive aircraft is hidden from others');
select pg_temp.as_user(1);
select is((select registration from public.get_person_checkins(pg_temp.u(1)) where id = '91000000-0000-0000-0000-000000000004'), 'D-SEPC',
          'but not from its owner');
select pg_temp.as_user(2);
select is((select salutes from public.get_person_checkins(pg_temp.u(1)) where id = '91000000-0000-0000-0000-000000000001'), 1, 'salute counts come with it');
select is((select comments from public.get_person_checkins(pg_temp.u(1)) where id = '91000000-0000-0000-0000-000000000001'), 1, 'and comment counts');
select is((select saluted from public.get_person_checkins(pg_temp.u(1)) where id = '91000000-0000-0000-0000-000000000001'), true, 'and whether the caller saluted');
select is((select count(*)::int from public.get_person_checkins(pg_temp.u(2))), 0, 'someone without check-ins gives an empty list');

-- Paging
select pg_temp.as_user(1);
select is((select string_agg(right(id::text, 1), ',' order by occurred_at desc, id desc)
           from public.get_person_checkins(pg_temp.u(1), page_size => 2)), '5,4', 'a page holds as many as asked');
select is((select string_agg(right(id::text, 1), ',' order by occurred_at desc, id desc)
           from public.get_person_checkins(pg_temp.u(1), (select occurred_at from public.checkins where id = '91000000-0000-0000-0000-000000000004'),
                                           '91000000-0000-0000-0000-000000000004', 2)), '3,2', 'the next page starts after the cursor');

select set_config('role', 'anon', true), set_config('request.jwt.claims', '', true);
select throws_ok($$ select * from public.get_person_checkins('00000000-0000-0000-0000-000000000001') $$, '42501', null, 'anonymous visitors cannot call it');

select * from finish();
rollback;
