-- Milestone 8b: the data export holds the caller's data, and only that.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

insert into auth.users (id, aud, role, email)
select ('00000000-0000-0000-0000-0000000007' || lpad(n::text, 2, '0'))::uuid, 'authenticated', 'authenticated',
       'export' || n || '@example.test'
from generate_series(1, 3) n;

create function pg_temp.as_user(n integer) returns void language sql as $$
  select set_config('request.jwt.claims',
           json_build_object('sub', '00000000-0000-0000-0000-0000000007' || lpad(n::text, 2, '0'), 'role', 'authenticated')::text, true),
         set_config('role', 'authenticated', true);
$$;
create function pg_temp.as_owner() returns void language sql as $$
  select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
$$;
create function pg_temp.u(n integer) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000007' || lpad(n::text, 2, '0'))::uuid;
$$;

insert into public.airports (id, icao, iata, name, country_code, continent, location)
  values (81, 'EDDF', 'FRA', 'Frankfurt', 'DE', 'EU', 'POINT(8.57 50.03)');
insert into public.aircraft_types (icao_code, manufacturer, model) values ('A320', 'Airbus', 'A320');
insert into public.aircraft (id, registration, type_icao) values (921, 'D-AIEX', 'A320');

insert into public.checkins (id, user_id, kind, occurred_at, visibility, aircraft_id, airport_id, location, note) values
  ('71000000-0000-0000-0000-000000000001', pg_temp.u(1), 'spotted', now() - interval '2 hours', 'private', 921, 81, 'POINT(8.5 50.0)', 'my note'),
  ('71000000-0000-0000-0000-000000000002', pg_temp.u(2), 'spotted', now() - interval '2 hours', 'public',  921, 81, 'POINT(1 2)', 'their note');
insert into public.checkin_photos (id, checkin_id, storage_path, width, height, position) values
  ('72000000-0000-0000-0000-000000000001', '71000000-0000-0000-0000-000000000001', 'u1/x/y.jpg', 800, 600, 0),
  ('72000000-0000-0000-0000-000000000002', '71000000-0000-0000-0000-000000000002', 'u2/x/y.jpg', 800, 600, 0);
insert into public.follows (follower, followee) values (pg_temp.u(1), pg_temp.u(2)), (pg_temp.u(2), pg_temp.u(1)), (pg_temp.u(3), pg_temp.u(1));
insert into public.blocks (blocker, blocked) values (pg_temp.u(1), pg_temp.u(3));
insert into public.salutes (user_id, checkin_id) values (pg_temp.u(1), '71000000-0000-0000-0000-000000000002'),
  (pg_temp.u(2), '71000000-0000-0000-0000-000000000001');
insert into public.comments (checkin_id, user_id, body) values
  ('71000000-0000-0000-0000-000000000002', pg_temp.u(1), 'my comment'),
  ('71000000-0000-0000-0000-000000000001', pg_temp.u(2), 'their comment');
insert into public.devices (id, user_id, platform, push_token, app_version) values
  ('73000000-0000-0000-0000-000000000001', pg_temp.u(1), 'ios', 'secret-push-token', '0.2.0');
insert into public.reports (reporter, target_type, target_id, reason) values (pg_temp.u(1), 'user', pg_temp.u(2)::text, 'spam');

select pg_temp.as_user(1);
create temp table export as select public.export_my_data() as doc;
grant select on export to authenticated;

select is((doc -> 'profile' ->> 'id')::uuid, pg_temp.u(1), 'the profile is the caller''s') from export;
select is(jsonb_array_length(doc -> 'checkins'), 1, 'only the caller''s check-ins') from export;
select is(doc -> 'checkins' -> 0 ->> 'registration', 'D-AIEX', 'a check-in carries the registration') from export;
select is(doc -> 'checkins' -> 0 ->> 'airport_code', 'FRA', 'and the airport code') from export;
select is((doc -> 'checkins' -> 0 ->> 'latitude')::numeric, 50.0, 'and the latitude of its own location') from export;
select is(doc -> 'checkins' -> 0 ->> 'note', 'my note', 'and the note') from export;
select ok(not (doc -> 'checkins' -> 0) ? 'user_id', 'without repeating the user ID') from export;
select is(jsonb_array_length(doc -> 'photos'), 1, 'only the caller''s photos') from export;
select ok(not (doc -> 'photos' -> 0) ? 'storage_path', 'and no storage path') from export;
select is(jsonb_array_length(doc -> 'comments_written'), 1, 'only the comments the caller wrote') from export;
select is(doc -> 'comments_written' -> 0 ->> 'body', 'my comment', 'with their text') from export;
select is(jsonb_array_length(doc -> 'salutes_given'), 1, 'the salutes the caller gave') from export;
select is(doc -> 'following' -> 0 ->> 'username', (select username from public.profiles where id = pg_temp.u(2)), 'who the caller follows') from export;
select is(jsonb_array_length(doc -> 'followers'), 1, 'and who follows the caller (blocking ended the other follow)') from export;
select is(jsonb_array_length(doc -> 'blocked'), 1, 'and who the caller blocked') from export;
select is(jsonb_array_length(doc -> 'reports_filed'), 1, 'and the reports the caller filed') from export;
select is(jsonb_array_length(doc -> 'devices'), 1, 'the devices') from export;
select ok(position('secret-push-token' in doc::text) = 0, 'but never a push token') from export;
select ok(position('their note' in doc::text) = 0 and position('their comment' in doc::text) = 0, 'and nothing written by other people') from export;

select pg_temp.as_owner();
select pg_temp.as_user(2);
select is((public.export_my_data() -> 'profile' ->> 'id')::uuid, pg_temp.u(2), 'another person gets their own export');
select is(jsonb_array_length(public.export_my_data() -> 'checkins'), 1, 'with their own check-ins only');

select set_config('role', 'anon', true), set_config('request.jwt.claims', '', true);
select throws_ok($$ select public.export_my_data() $$, '42501', null, 'anonymous visitors cannot export');

select * from finish();
rollback;
