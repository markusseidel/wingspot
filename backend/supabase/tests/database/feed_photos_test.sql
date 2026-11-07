-- Milestone 7f: who can see a photo's row and file.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

-- viewer 1, public author 2, friend 3, blocked 5
insert into auth.users (id, aud, role, email)
select ('00000000-0000-0000-0000-0000000006' || lpad(n::text, 2, '0'))::uuid, 'authenticated', 'authenticated', 'fphoto' || n || '@example.test'
from generate_series(1, 5) n;

create function pg_temp.as_user(n integer) returns void language sql as $$
  select set_config('request.jwt.claims',
           json_build_object('sub', '00000000-0000-0000-0000-0000000006' || lpad(n::text, 2, '0'), 'role', 'authenticated')::text, true),
         set_config('role', 'authenticated', true);
$$;
create function pg_temp.as_anon() returns void language sql as $$
  select set_config('request.jwt.claims', '', true), set_config('role', 'anon', true);
$$;
create function pg_temp.u(n integer) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000006' || lpad(n::text, 2, '0'))::uuid;
$$;

insert into public.aircraft_types (icao_code, manufacturer, model) values ('A320', 'Airbus', 'A320');
insert into public.aircraft (id, registration, type_icao, is_sensitive) values
  (911, 'D-AIPH', 'A320', false), (912, 'D-SEPH', 'A320', true);

insert into public.follows (follower, followee) values
  (pg_temp.u(1), pg_temp.u(2)), (pg_temp.u(1), pg_temp.u(3)), (pg_temp.u(3), pg_temp.u(1)), (pg_temp.u(1), pg_temp.u(5));
insert into public.blocks (blocker, blocked) values (pg_temp.u(1), pg_temp.u(5));

-- 1: public (author 2), 2: private (author 2), 3: friends, sensitive aircraft (author 3), 4: friends, ordinary (author 3),
-- 5: public (author 5, blocked by the viewer)
insert into public.checkins (id, user_id, kind, occurred_at, visibility, aircraft_id) values
  ('51000000-0000-0000-0000-000000000001', pg_temp.u(2), 'spotted', now() - interval '3 hours', 'public',  911),
  ('51000000-0000-0000-0000-000000000002', pg_temp.u(2), 'spotted', now() - interval '3 hours', 'private', 911),
  ('51000000-0000-0000-0000-000000000003', pg_temp.u(3), 'spotted', now() - interval '3 hours', 'friends', 912),
  ('51000000-0000-0000-0000-000000000004', pg_temp.u(3), 'spotted', now() - interval '3 hours', 'friends', 911),
  ('51000000-0000-0000-0000-000000000005', pg_temp.u(5), 'spotted', now() - interval '3 hours', 'public',  911);
-- One photo per check-in, with its file in storage.
create function pg_temp.path(author integer, n integer) returns text language sql as $$
  select pg_temp.u(author)::text || '/51000000-0000-0000-0000-00000000000' || n || '/52000000-0000-0000-0000-00000000000' || n || '.jpg';
$$;
insert into public.checkin_photos (id, checkin_id, storage_path)
select ('52000000-0000-0000-0000-00000000000' || n)::uuid, ('51000000-0000-0000-0000-00000000000' || n)::uuid,
       pg_temp.path(case n when 1 then 2 when 2 then 2 when 5 then 5 else 3 end, n)
from generate_series(1, 5) n;
insert into storage.objects (bucket_id, name, owner)
select 'photos', storage_path, null from public.checkin_photos;

select pg_temp.as_user(1);
select is((select count(*)::int from public.checkin_photos where id = '52000000-0000-0000-0000-000000000001'), 1, 'a public check-in''s photo row is visible');
select is((select count(*)::int from storage.objects where bucket_id = 'photos' and name = pg_temp.path(2, 1)), 1, 'and its file');
select is((select count(*)::int from public.checkin_photos where id = '52000000-0000-0000-0000-000000000002'), 0, 'a private check-in''s photo row stays hidden');
select is((select count(*)::int from storage.objects where bucket_id = 'photos' and name = pg_temp.path(2, 2)), 0, 'and its file');
select is((select count(*)::int from public.checkin_photos where id = '52000000-0000-0000-0000-000000000004'), 1, 'a friend''s photo is visible');
select is((select count(*)::int from storage.objects where bucket_id = 'photos' and name = pg_temp.path(3, 4)), 1, 'and its file');
select is((select count(*)::int from public.checkin_photos where id = '52000000-0000-0000-0000-000000000003'), 0, 'a photo of a sensitive aircraft is hidden from others');
select is((select count(*)::int from storage.objects where bucket_id = 'photos' and name = pg_temp.path(3, 3)), 0, 'and its file');
select is((select count(*)::int from public.checkin_photos where id = '52000000-0000-0000-0000-000000000005'), 0, 'a blocked person''s photo is hidden');
select is((select count(*)::int from storage.objects where bucket_id = 'photos' and name = pg_temp.path(5, 5)), 0, 'and its file');

select pg_temp.as_user(3);
select is((select count(*)::int from public.checkin_photos where id = '52000000-0000-0000-0000-000000000003'), 1, 'the owner still sees a photo of a sensitive aircraft');
select pg_temp.as_user(5);
select is((select count(*)::int from public.checkin_photos where id in ('52000000-0000-0000-0000-000000000002', '52000000-0000-0000-0000-000000000004')), 0, 'a stranger sees no private or friends-only photo');

select pg_temp.as_anon();
select is((select count(*)::int from public.checkin_photos), 2, 'anonymous visitors see only the rows of public check-ins');
select is((select count(*)::int from storage.objects where bucket_id = 'photos'), 0, 'anonymous visitors see no files');

select pg_temp.as_user(1);
select is(public.report('photo', '52000000-0000-0000-0000-000000000001', 'test'), 'reported', 'a visible photo can be reported');
select is(public.report('photo', '52000000-0000-0000-0000-000000000003', 'test'), 'unknown_target', 'a hidden photo cannot');

select * from finish();
rollback;
