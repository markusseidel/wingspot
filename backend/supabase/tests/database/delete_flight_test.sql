-- Deleting a flight deletes the two airport visits it created, and nothing else.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

insert into auth.users (id, aud, role, email) values
  ('00000000-0000-0000-0000-000000000c01', 'authenticated', 'authenticated', 'delflight@example.test'),
  ('00000000-0000-0000-0000-000000000c02', 'authenticated', 'authenticated', 'delflight2@example.test');
insert into public.airports (id, icao, iata, name, country_code, continent, location) values
  (893001, 'ZZZG', 'ZZG', 'Delete flight A', 'DE', 'EU', 'POINT(8 50)'),
  (893002, 'ZZZH', 'ZZH', 'Delete flight B', 'DE', 'EU', 'POINT(9 51)');
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000c01', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);

select public.sync_checkins(jsonb_build_array(
  jsonb_build_object('id', 'c0000000-0000-7000-8000-000000000001', 'kind', 'flown', 'occurred_at', '2026-03-01T10:00:00Z', 'origin_id', 893001, 'destination_id', 893002),
  jsonb_build_object('id', 'c0000000-0000-7000-8000-000000000002', 'kind', 'airport', 'occurred_at', '2026-03-01T10:00:00Z', 'airport_id', 893001, 'context', 'departing'),
  jsonb_build_object('id', 'c0000000-0000-7000-8000-000000000003', 'kind', 'airport', 'occurred_at', '2026-03-01T10:00:00Z', 'airport_id', 893002, 'context', 'arriving'),
  jsonb_build_object('id', 'c0000000-0000-7000-8000-000000000004', 'kind', 'airport', 'occurred_at', '2026-03-01T10:00:00Z', 'airport_id', 893002, 'context', 'spotting'),
  jsonb_build_object('id', 'c0000000-0000-7000-8000-000000000005', 'kind', 'airport', 'occurred_at', '2026-03-05T10:00:00Z', 'airport_id', 893001, 'context', 'departing'),
  -- a second flight at the same time between the same airports, with its own visits
  jsonb_build_object('id', 'c0000000-0000-7000-8000-000000000006', 'kind', 'flown', 'occurred_at', '2026-04-01T10:00:00Z', 'origin_id', 893001, 'destination_id', 893002),
  jsonb_build_object('id', 'c0000000-0000-7000-8000-000000000007', 'kind', 'flown', 'occurred_at', '2026-04-01T10:00:00Z', 'origin_id', 893001, 'destination_id', 893002),
  jsonb_build_object('id', 'c0000000-0000-7000-8000-000000000008', 'kind', 'airport', 'occurred_at', '2026-04-01T10:00:00Z', 'airport_id', 893001, 'context', 'departing')));

select public.delete_checkin('c0000000-0000-7000-8000-000000000001');

select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
select is((select count(*)::int from public.checkins where id = 'c0000000-0000-7000-8000-000000000001'), 0, 'the flight is gone');
select is((select count(*)::int from public.checkins where id in ('c0000000-0000-7000-8000-000000000002', 'c0000000-0000-7000-8000-000000000003')), 0, 'so are its two visits');
select is((select count(*)::int from public.checkins where id = 'c0000000-0000-7000-8000-000000000004'), 1, 'a spotting visit at the same time stays');
select is((select count(*)::int from public.checkins where id = 'c0000000-0000-7000-8000-000000000005'), 1, 'a visit at another time stays');

-- Two flights at the same time: deleting one leaves the visits, deleting the other takes them
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000c01', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);
select public.delete_checkin('c0000000-0000-7000-8000-000000000006');
select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
select is((select count(*)::int from public.checkins where id = 'c0000000-0000-7000-8000-000000000008'), 1, 'visits stay while another flight at that time uses the airport');
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000c01', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);
select public.delete_checkin('c0000000-0000-7000-8000-000000000007');
select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
select is((select count(*)::int from public.checkins where id = 'c0000000-0000-7000-8000-000000000008'), 0, 'and go with the last one');

-- Another user cannot delete the flight or its visits
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000c01', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);
select public.sync_checkins(jsonb_build_array(
  jsonb_build_object('id', 'c0000000-0000-7000-8000-000000000009', 'kind', 'flown', 'occurred_at', '2026-05-01T10:00:00Z', 'origin_id', 893001, 'destination_id', 893002),
  jsonb_build_object('id', 'c0000000-0000-7000-8000-00000000000a', 'kind', 'airport', 'occurred_at', '2026-05-01T10:00:00Z', 'airport_id', 893001, 'context', 'departing')));
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000c02', 'role', 'authenticated')::text, true);
select public.delete_checkin('c0000000-0000-7000-8000-000000000009');
select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
select is((select count(*)::int from public.checkins where id in ('c0000000-0000-7000-8000-000000000009', 'c0000000-0000-7000-8000-00000000000a')), 2, 'someone else deleting it changes nothing');

select * from finish();
rollback;
