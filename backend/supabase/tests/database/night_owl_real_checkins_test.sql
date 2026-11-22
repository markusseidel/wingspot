-- Time-of-day badges count only check-ins where the person was at the airport, not flights (issue #277).
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

insert into auth.users (id, aud, role, email) values
  ('00000000-0000-0000-0000-0000000000e1', 'authenticated', 'authenticated', 'nightowl1@example.test'),
  ('00000000-0000-0000-0000-0000000000e2', 'authenticated', 'authenticated', 'nightowl2@example.test');
-- A made-up airport far to the east (longitude 150: 10 hours ahead of UTC) and one in Europe
insert into public.airports (id, icao, iata, name, country_code, continent, location) values
  (898001, 'ZZZR', 'ZZR', 'Night owl east', 'JP', 'AS', 'POINT(150 36)'),
  (898002, 'ZZZS', 'ZZS', 'Night owl west', 'DE', 'EU', 'POINT(8 50)');

create function pg_temp.value(uid uuid, badge text) returns bigint language sql as $$
  select value from private.badge_values(uid) where badge_id = badge;
$$;

-- A flight from Europe to the far east, logged at 17:03 UTC, with its two visits: for the far airport that is 03:03 "local"
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000e1', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);
select public.sync_checkins(jsonb_build_array(
  jsonb_build_object('id', 'e0000000-0000-7000-8000-000000000001', 'kind', 'flown', 'occurred_at', '2026-03-01T17:03:00Z', 'origin_id', 898002, 'destination_id', 898001),
  jsonb_build_object('id', 'e0000000-0000-7000-8000-000000000002', 'kind', 'airport', 'occurred_at', '2026-03-01T17:03:00Z', 'airport_id', 898002, 'context', 'departing', 'flight_id', 'e0000000-0000-7000-8000-000000000001'),
  jsonb_build_object('id', 'e0000000-0000-7000-8000-000000000003', 'kind', 'airport', 'occurred_at', '2026-03-01T17:03:00Z', 'airport_id', 898001, 'context', 'arriving', 'flight_id', 'e0000000-0000-7000-8000-000000000001')));
select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
select is(pg_temp.value('00000000-0000-0000-0000-0000000000e1', 'night_owl'), 0::bigint, 'a flight and its visits do not count for Night Owl');
select is(pg_temp.value('00000000-0000-0000-0000-0000000000e1', 'early_bird'), 0::bigint, 'nor for Early Bird');
select is((select level from public.user_badges where user_id = '00000000-0000-0000-0000-0000000000e1' and badge_id = 'night_owl'), null, 'and the badge is not earned');

-- An old-style flight visit without the link, at the flight's time and airport, does not count either
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000e2', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);
select public.sync_checkins(jsonb_build_array(
  jsonb_build_object('id', 'e0000000-0000-7000-8000-000000000011', 'kind', 'flown', 'occurred_at', '2026-03-02T17:03:00Z', 'origin_id', 898002, 'destination_id', 898001),
  jsonb_build_object('id', 'e0000000-0000-7000-8000-000000000012', 'kind', 'airport', 'occurred_at', '2026-03-02T17:03:00Z', 'airport_id', 898001, 'context', 'arriving')));
select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
select is(pg_temp.value('00000000-0000-0000-0000-0000000000e2', 'night_owl'), 0::bigint, 'a visit without the link at a flight''s time and airport does not count');

-- A standalone airport check-in where it really is 03:03 does count (17:03 UTC at longitude 150 is 03:03 the next day)
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000e2', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);
select public.sync_checkins(jsonb_build_array(
  jsonb_build_object('id', 'e0000000-0000-7000-8000-000000000013', 'kind', 'airport', 'occurred_at', '2026-03-05T17:03:00Z', 'airport_id', 898001, 'context', 'spotting')));
select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
select is(pg_temp.value('00000000-0000-0000-0000-0000000000e2', 'night_owl'), 1::bigint, 'a standalone airport check-in at local night counts');
select is(pg_temp.value('00000000-0000-0000-0000-0000000000e2', 'early_bird'), 0::bigint, 'and is not an early bird');
select ok((select level from public.user_badges where user_id = '00000000-0000-0000-0000-0000000000e2' and badge_id = 'night_owl') >= 1, 'so the badge is earned');

select * from finish();
rollback;
