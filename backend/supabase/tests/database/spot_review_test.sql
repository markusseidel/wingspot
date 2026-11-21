-- Reviewing suggested spotting locations: roles, the waiting list, a decision and the note to the author.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

-- 1 = founder, 2 = moderator, 3 = author, 4 = another person
insert into auth.users (id, aud, role, email)
select ('00000000-0000-0000-0000-0000000010' || lpad(n::text, 2, '0'))::uuid, 'authenticated', 'authenticated', 'rev' || n || '@example.test'
from generate_series(1, 4) n;
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
insert into public.airports (id, icao, iata, name, country_code, continent, location) values
  (898001, 'ZZRA', 'ZRA', 'Review airport', 'DE', 'EU', 'POINT(8 50)');
insert into public.staff_roles (user_id, role, show_label) values (pg_temp.u(1), 'founder', true), (pg_temp.u(2), 'moderator', false);

-- Permissions and labels ---------------------------------------------------------------------------------------
select pg_temp.as_user(1);
select is(public.my_permissions(), array['review_spots', 'manage_staff'], 'the founder may review and manage staff');
select pg_temp.reset_role(); select pg_temp.as_user(2);
select is(public.my_permissions(), array['review_spots'], 'a moderator may review');
select pg_temp.reset_role(); select pg_temp.as_user(4);
select is(public.my_permissions(), array[]::text[], 'everyone else may do nothing');
select is(public.staff_label(pg_temp.u(1)), 'founder', 'the founder label is shown to everyone');
select is(public.staff_label(pg_temp.u(2)), null, 'a moderator label stays hidden unless chosen');
select throws_ok($$select count(*) from public.staff_roles$$, '42501', null, 'the roles table cannot be read directly');

-- Two places wait ---------------------------------------------------------------------------------------------
select pg_temp.reset_role(); select pg_temp.as_user(3);
select is((public.add_spotting_location('Terrace one', 50.001, 8.001, 'About one') ->> 'status'), 'pending', 'author suggests one');
select is((public.add_spotting_location('Terrace two', 50.05, 8.05) ->> 'status'), 'pending', 'and another');
select pg_temp.reset_role();
select set_config('t.one', (select id::text from public.spotting_locations where name = 'Terrace one'), true),
       set_config('t.two', (select id::text from public.spotting_locations where name = 'Terrace two'), true);
select pg_temp.as_user(3);
select is((select count(*)::int from public.pending_spots()), 0, 'the author cannot list what waits');
select is((public.review_spot(current_setting('t.one')::int, true) ->> 'code'), 'not_allowed',
  'nor decide');

select pg_temp.reset_role(); select pg_temp.as_user(2);
select is((select count(*)::int from public.pending_spots()), 2, 'a moderator sees both');
select is((select author_username from public.pending_spots() where name = 'Terrace one'),
  (select username from public.profiles where id = pg_temp.u(3)), 'with the author');
select is((select airport_code from public.pending_spots() where name = 'Terrace one'), 'ZRA', 'and the airport');

-- Approve ------------------------------------------------------------------------------------------------------
select is((public.review_spot(current_setting('t.one')::int, true) ->> 'status'), 'approved', 'approved');
select pg_temp.reset_role();
select is((select kind from public.notifications where recipient = pg_temp.u(3) order by created_at desc limit 1), 'spot_approved',
  'the author is told');
select is((select snippet from public.notifications where recipient = pg_temp.u(3) and kind = 'spot_approved'), 'Terrace one',
  'with the name of the place');
select is((select reviewed_by from public.spotting_locations where name = 'Terrace one'), pg_temp.u(2), 'who decided is stored');
select pg_temp.as_user(4);
select is((select count(*)::int from public.spotting_locations_at(898001)), 1, 'everyone sees the approved place');

-- Reject with a reason -----------------------------------------------------------------------------------------
select pg_temp.reset_role(); select pg_temp.as_user(1);
select is((public.review_spot(current_setting('t.two')::int, false, '  Inside the fence  ') ->> 'status'),
  'rejected', 'rejected');
select is((public.review_spot(current_setting('t.two')::int, true) ->> 'code'), 'not_pending',
  'a decided place cannot be decided again');
select pg_temp.reset_role();
select is((select snippet from public.notifications where recipient = pg_temp.u(3) and kind = 'spot_rejected'),
  E'Terrace two\nInside the fence', 'the author gets the reason');
select pg_temp.as_user(3);
select is((select count(*)::int from public.spotting_locations_at(898001)), 1, 'a rejected place is gone for its author too');
select is((public.add_spotting_location('Terrace two', 50.05, 8.05) ->> 'status'), 'pending', 'and the same place can be suggested again');
select is((select count(*)::int from public.get_notifications()), 2, 'both decisions are in the inbox');

select * from finish();
rollback;
