-- What the check-in page shows about spotting locations. Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

insert into auth.users (id, aud, role, email)
select ('00000000-0000-0000-0000-0000000010' || lpad(n::text, 2, '0'))::uuid, 'authenticated', 'authenticated', 'cspot' || n || '@example.test'
from generate_series(1, 2) n;
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
  (898001, 'ZZCA', 'ZCA', 'Check-in spot airport', 'DE', 'EU', 'POINT(8 50)');
update public.profiles set is_private = false where id in (pg_temp.u(1), pg_temp.u(2));
insert into public.spotting_locations (id, airport_id, name, location, status)
values (898100, 898001, 'North fence', 'POINT(8.001 50.001)', 'approved');

select pg_temp.as_user(1);
select public.sync_checkins(jsonb_build_array(
  jsonb_build_object('id', 'c9000000-0000-7000-8000-000000000001', 'kind', 'airport', 'occurred_at', '2026-03-01T08:00:00Z',
                     'airport_id', 898001, 'context', 'spotting', 'visibility', 'public', 'spot_location_id', 898100),
  jsonb_build_object('id', 'c9000000-0000-7000-8000-000000000002', 'kind', 'spotted', 'occurred_at', '2026-03-01T08:10:00Z',
                     'registration', 'D-ABCA', 'visibility', 'public', 'visit_id', 'c9000000-0000-7000-8000-000000000001'),
  jsonb_build_object('id', 'c9000000-0000-7000-8000-000000000003', 'kind', 'spotted', 'occurred_at', '2026-03-01T09:10:00Z',
                     'registration', 'D-ABCB', 'visibility', 'private')));
select is((public.get_checkin_spot('c9000000-0000-7000-8000-000000000001') ->> 'spot_name'), 'North fence', 'a visit names its place');
select is((public.get_checkin_spot('c9000000-0000-7000-8000-000000000001') ->> 'sightings'), '1', 'and counts its aircraft');
select is((public.get_checkin_spot('c9000000-0000-7000-8000-000000000002') ->> 'spot_name'), 'North fence', 'a sighting names the place of its visit');
select is((public.get_checkin_spot('c9000000-0000-7000-8000-000000000002') ->> 'visit_id'), 'c9000000-0000-7000-8000-000000000001', 'and its visit');
select is(public.get_checkin_spot('c9000000-0000-7000-8000-000000000003'), null, 'a sighting without a visit has nothing to show');
select pg_temp.reset_role();

select pg_temp.as_user(2);
select is((public.get_checkin_spot('c9000000-0000-7000-8000-000000000001') ->> 'sightings'), '1', 'a stranger sees the public sighting count');
select is(public.get_checkin_spot('c9000000-0000-7000-8000-000000000003'), null, 'and nothing of a private check-in');
select pg_temp.reset_role();

select finish();
rollback;
