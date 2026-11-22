-- Reviewers are told when a place is suggested (issue #279).
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

-- 1 = founder, 2 = moderator, 3 = author, 4 = another person, 5 = a second founder who is also the author of one place
insert into auth.users (id, aud, role, email)
select ('00000000-0000-0000-0000-0000000020' || lpad(n::text, 2, '0'))::uuid, 'authenticated', 'authenticated', 'prop' || n || '@example.test'
from generate_series(1, 5) n;
create function pg_temp.u(n integer) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000020' || lpad(n::text, 2, '0'))::uuid;
$$;
create function pg_temp.as_user(n integer) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true),
         set_config('role', 'authenticated', true);
$$;
create function pg_temp.reset_role() returns void language sql as $$
  select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
$$;
create function pg_temp.spot_id(n text) returns integer language sql security definer as $$
  select id from public.spotting_locations where name = n;
$$;
insert into public.airports (id, icao, iata, name, country_code, continent, location) values
  (898101, 'ZZRB', 'ZRB', 'Proposed airport', 'DE', 'EU', 'POINT(8 50)');
insert into public.staff_roles (user_id, role, show_label) values
  (pg_temp.u(1), 'founder', true), (pg_temp.u(2), 'moderator', false), (pg_temp.u(5), 'founder', false);

select pg_temp.as_user(3);
select is((public.add_spotting_location('Terrace one', 50.001, 8.001, 'About one') ->> 'status'), 'pending', 'a person suggests a place');
select pg_temp.reset_role();

select is((select count(*)::int from public.notifications where kind = 'spot_proposed' and recipient = pg_temp.u(1)), 1, 'the founder is told');
select is((select count(*)::int from public.notifications where kind = 'spot_proposed' and recipient = pg_temp.u(2)), 1, 'so is a moderator');
select is((select count(*)::int from public.notifications where kind = 'spot_proposed' and recipient = pg_temp.u(5)), 1, 'and every other reviewer');
select is((select count(*)::int from public.notifications where kind = 'spot_proposed' and recipient in (pg_temp.u(3), pg_temp.u(4))), 0, 'nobody else is');
select is((select snippet from public.notifications where kind = 'spot_proposed' and recipient = pg_temp.u(1)), 'Terrace one', 'the note carries the name of the place');
select is((select actor from public.notifications where kind = 'spot_proposed' and recipient = pg_temp.u(1)), pg_temp.u(3), 'and who suggested it');

-- A second place within the hour is another note: the duplicate check does not apply to this kind
select pg_temp.as_user(3);
select public.add_spotting_location('Terrace two', 50.05, 8.05);
select pg_temp.reset_role();
select is((select count(*)::int from public.notifications where kind = 'spot_proposed' and recipient = pg_temp.u(1)), 2, 'two places, two notes');

-- A reviewer who suggests a place is not told about their own
select pg_temp.as_user(5);
select public.add_spotting_location('Founder spot', 50.1, 8.1);
select pg_temp.reset_role();
select is((select count(*)::int from public.notifications where kind = 'spot_proposed' and recipient = pg_temp.u(5)), 2, 'a reviewer is told about the two places of others, not about their own');
select is((select count(*)::int from public.notifications where kind = 'spot_proposed' and recipient = pg_temp.u(1)), 3, 'but the other reviewers are');

-- Deciding on a place still tells the author, and nothing changed for that
select pg_temp.as_user(1);
select public.review_spot(pg_temp.spot_id('Terrace one'), true, null);
select pg_temp.reset_role();
select is((select count(*)::int from public.notifications where kind = 'spot_approved' and recipient = pg_temp.u(3)), 1, 'the author is still told about the decision');

select * from finish();
rollback;
