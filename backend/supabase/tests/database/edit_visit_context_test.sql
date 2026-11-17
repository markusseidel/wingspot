-- The reason for an airport visit and the aircraft of a sighting can be corrected by sending the check-in again.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

insert into auth.users (id, aud, role, email) values
  ('00000000-0000-0000-0000-000000000b11', 'authenticated', 'authenticated', 'editvisit@example.test');
insert into public.airports (id, icao, iata, name, country_code, continent, location) values
  (893001, 'ZZZG', 'ZZG', 'Edit visit', 'DE', 'EU', 'POINT(8 50)');
insert into public.aircraft_types (icao_code, manufacturer, model) values ('B748', 'Boeing', '747-8') on conflict do nothing;
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000b11', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);

select public.sync_checkins(jsonb_build_array(
  jsonb_build_object('id', 'c0000000-0000-7000-8000-000000000001', 'kind', 'airport', 'occurred_at', '2026-03-01T10:00:00Z', 'airport_id', 893001, 'context', 'spotting'),
  jsonb_build_object('id', 'c0000000-0000-7000-8000-000000000002', 'kind', 'spotted', 'occurred_at', '2026-03-01T10:00:00Z', 'registration', 'DAIMA')));
select public.sync_checkins(jsonb_build_array(
  jsonb_build_object('id', 'c0000000-0000-7000-8000-000000000001', 'kind', 'airport', 'occurred_at', '2026-03-01T10:00:00Z', 'airport_id', 893001, 'context', 'arriving'),
  jsonb_build_object('id', 'c0000000-0000-7000-8000-000000000002', 'kind', 'spotted', 'occurred_at', '2026-03-01T10:00:00Z', 'registration', 'DAIMB', 'type_icao', 'B748')));

select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
select is((select visit_context from public.checkins where id = 'c0000000-0000-7000-8000-000000000001'), 'arriving', 'the reason for the visit is corrected');
select is((select a.registration from public.checkins c join public.aircraft a on a.id = c.aircraft_id where c.id = 'c0000000-0000-7000-8000-000000000002'), 'DAIMB', 'the registration of a sighting is corrected');
select is((select type_icao from public.checkins where id = 'c0000000-0000-7000-8000-000000000002'), 'B748', 'and its type');
select is((select occurred_at from public.checkins where id = 'c0000000-0000-7000-8000-000000000001'), '2026-03-01T10:00:00Z'::timestamptz, 'the time stays');

select * from finish();
rollback;
