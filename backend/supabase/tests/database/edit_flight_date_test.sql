-- Correcting the day of a flight moves the flight and its two airport visits. A standalone visit has its own date (#312).
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

insert into auth.users (id, aud, role, email) values
  ('00000000-0000-0000-0000-000000000b01', 'authenticated', 'authenticated', 'editdate@example.test');
insert into public.airports (id, icao, iata, name, country_code, continent, location) values
  (892001, 'ZZZE', 'ZZE', 'Edit date A', 'DE', 'EU', 'POINT(8 50)'),
  (892002, 'ZZZF', 'ZZF', 'Edit date B', 'DE', 'EU', 'POINT(9 51)');
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000b01', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);

select public.sync_checkins(jsonb_build_array(
  jsonb_build_object('id', 'b0000000-0000-7000-8000-000000000001', 'kind', 'flown', 'occurred_at', '2026-03-01T10:00:00Z', 'origin_id', 892001, 'destination_id', 892002),
  jsonb_build_object('id', 'b0000000-0000-7000-8000-000000000002', 'kind', 'airport', 'occurred_at', '2026-03-01T10:00:00Z', 'airport_id', 892001, 'context', 'departing'),
  jsonb_build_object('id', 'b0000000-0000-7000-8000-000000000003', 'kind', 'airport', 'occurred_at', '2026-03-01T10:00:00Z', 'airport_id', 892002, 'context', 'arriving'),
  jsonb_build_object('id', 'b0000000-0000-7000-8000-000000000004', 'kind', 'airport', 'occurred_at', '2026-03-01T10:00:00Z', 'airport_id', 892002, 'context', 'spotting')));

-- The same flight again with another day, and a spotting visit sent again with another day too
select public.sync_checkins(jsonb_build_array(
  jsonb_build_object('id', 'b0000000-0000-7000-8000-000000000001', 'kind', 'flown', 'occurred_at', '2026-02-20T12:00:00Z', 'origin_id', 892001, 'destination_id', 892002),
  jsonb_build_object('id', 'b0000000-0000-7000-8000-000000000004', 'kind', 'airport', 'occurred_at', '2026-02-21T12:00:00Z', 'airport_id', 892002, 'context', 'spotting')));

select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
select is((select occurred_at from public.checkins where id = 'b0000000-0000-7000-8000-000000000001'), '2026-02-20T12:00:00Z'::timestamptz, 'the flight has the new day');
select is((select occurred_at from public.checkins where id = 'b0000000-0000-7000-8000-000000000002'), '2026-02-20T12:00:00Z'::timestamptz, 'so has its departure visit');
select is((select occurred_at from public.checkins where id = 'b0000000-0000-7000-8000-000000000003'), '2026-02-20T12:00:00Z'::timestamptz, 'and its arrival visit');
select is((select occurred_at from public.checkins where id = 'b0000000-0000-7000-8000-000000000004'), '2026-02-21T12:00:00Z'::timestamptz, 'a standalone spotting visit takes the time that is sent (backdated check-ins, #312)');

select * from finish();
rollback;
