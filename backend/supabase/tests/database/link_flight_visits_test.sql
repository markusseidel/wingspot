-- A visit linked to its flight goes with it when the flight is deleted and moves with it when its day changes,
-- whatever the visit's own time says. Visits without the link are found by time and airports, as before.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

insert into auth.users (id, aud, role, email) values
  ('00000000-0000-0000-0000-000000000d01', 'authenticated', 'authenticated', 'linkflight@example.test');
insert into public.airports (id, icao, iata, name, country_code, continent, location) values
  (894001, 'ZZZI', 'ZZI', 'Link flight A', 'DE', 'EU', 'POINT(8 50)'),
  (894002, 'ZZZJ', 'ZZJ', 'Link flight B', 'DE', 'EU', 'POINT(9 51)');
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000d01', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);

-- Two flights at the same time between the same airports, each with its linked visits. A visit arrives before its flight.
select public.sync_checkins(jsonb_build_array(
  jsonb_build_object('id', 'd0000000-0000-7000-8000-000000000002', 'kind', 'airport', 'occurred_at', '2026-03-01T10:00:00Z', 'airport_id', 894001, 'context', 'departing', 'flight_id', 'd0000000-0000-7000-8000-000000000001'),
  jsonb_build_object('id', 'd0000000-0000-7000-8000-000000000001', 'kind', 'flown', 'occurred_at', '2026-03-01T10:00:00Z', 'origin_id', 894001, 'destination_id', 894002),
  jsonb_build_object('id', 'd0000000-0000-7000-8000-000000000003', 'kind', 'airport', 'occurred_at', '2026-03-01T10:00:00Z', 'airport_id', 894002, 'context', 'arriving', 'flight_id', 'd0000000-0000-7000-8000-000000000001'),
  jsonb_build_object('id', 'd0000000-0000-7000-8000-000000000011', 'kind', 'flown', 'occurred_at', '2026-03-01T10:00:00Z', 'origin_id', 894001, 'destination_id', 894002),
  jsonb_build_object('id', 'd0000000-0000-7000-8000-000000000012', 'kind', 'airport', 'occurred_at', '2026-03-01T10:00:00Z', 'airport_id', 894001, 'context', 'departing', 'flight_id', 'd0000000-0000-7000-8000-000000000011'),
  jsonb_build_object('id', 'd0000000-0000-7000-8000-000000000013', 'kind', 'airport', 'occurred_at', '2026-03-01T10:00:00Z', 'airport_id', 894002, 'context', 'arriving', 'flight_id', 'd0000000-0000-7000-8000-000000000011')));

select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
select is((select flight_id from public.checkins where id = 'd0000000-0000-7000-8000-000000000012'), 'd0000000-0000-7000-8000-000000000011'::uuid, 'the visit keeps the link it was sent with');
select is((select flight_id from public.checkins where id = 'd0000000-0000-7000-8000-000000000001'), null, 'a flight has no link');

-- Deleting the first flight deletes exactly its visits, although the other flight shares time and airports
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000d01', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);
select public.delete_checkin('d0000000-0000-7000-8000-000000000001');
select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
select is((select count(*)::int from public.checkins where id in ('d0000000-0000-7000-8000-000000000001', 'd0000000-0000-7000-8000-000000000002', 'd0000000-0000-7000-8000-000000000003')), 0, 'the flight and its linked visits are gone');
select is((select count(*)::int from public.checkins where id in ('d0000000-0000-7000-8000-000000000011', 'd0000000-0000-7000-8000-000000000012', 'd0000000-0000-7000-8000-000000000013')), 3, 'the other flight and its visits stay');

-- A linked visit moves with its flight even when its own time differs
update public.checkins set occurred_at = '2026-03-02T10:00:00Z' where id = 'd0000000-0000-7000-8000-000000000012';
update public.checkins set occurred_at = '2026-02-20T12:00:00Z' where id = 'd0000000-0000-7000-8000-000000000011';
select is((select occurred_at from public.checkins where id = 'd0000000-0000-7000-8000-000000000012'), '2026-02-20T12:00:00Z'::timestamptz, 'a linked visit moves with its flight');
select is((select occurred_at from public.checkins where id = 'd0000000-0000-7000-8000-000000000013'), '2026-02-20T12:00:00Z'::timestamptz, 'so does the other one');

-- Another user's flight cannot delete my visits through the link
insert into auth.users (id, aud, role, email) values
  ('00000000-0000-0000-0000-000000000d02', 'authenticated', 'authenticated', 'linkflight2@example.test');
insert into public.checkins (id, user_id, kind, occurred_at, origin_id, destination_id)
  values ('d0000000-0000-7000-8000-000000000021', '00000000-0000-0000-0000-000000000d02', 'flown', '2026-06-01T10:00:00Z', 894001, 894002);
insert into public.checkins (id, user_id, kind, occurred_at, airport_id, visit_context, flight_id)
  values ('d0000000-0000-7000-8000-000000000022', '00000000-0000-0000-0000-000000000d01', 'airport', '2026-06-01T10:00:00Z', 894001, 'departing', 'd0000000-0000-7000-8000-000000000021');
delete from public.checkins where id = 'd0000000-0000-7000-8000-000000000021';
select is((select count(*)::int from public.checkins where id = 'd0000000-0000-7000-8000-000000000022'), 1, 'a link to someone else''s flight deletes nothing');

select * from finish();
rollback;
