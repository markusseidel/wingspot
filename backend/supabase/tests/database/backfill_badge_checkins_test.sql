-- The one-time backfill of badge check-ins: the newest check-in at unlock time, and nothing else changes.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

insert into auth.users (id, aud, role, email) values
  ('00000000-0000-0000-0000-0000000000c1', 'authenticated', 'authenticated', 'backfill@example.test');
insert into public.airports (id, icao, iata, name, country_code, continent, location) values
  (897001, 'ZZZP', 'ZZP', 'Backfill A', 'DE', 'EU', 'POINT(8 50)');
insert into public.checkins (id, user_id, kind, occurred_at, created_at, visibility, airport_id, visit_context) values
  ('c1000000-0000-7000-8000-000000000001', '00000000-0000-0000-0000-0000000000c1', 'airport', '2020-01-01', '2026-02-01 10:00+00', 'public', 897001, 'spotting'),
  ('c1000000-0000-7000-8000-000000000002', '00000000-0000-0000-0000-0000000000c1', 'airport', '2020-01-02', '2026-03-01 10:00+00', 'public', 897001, 'spotting'),
  ('c1000000-0000-7000-8000-000000000003', '00000000-0000-0000-0000-0000000000c1', 'airport', '2020-01-03', '2026-04-01 10:00+00', 'public', 897001, 'spotting');
delete from public.user_badges where user_id = '00000000-0000-0000-0000-0000000000c1';
insert into public.user_badges (user_id, badge_id, level, progress, unlocked_at, checkin_id) values
  ('00000000-0000-0000-0000-0000000000c1', 'wheels_up', 1, 1, '2026-02-01 10:00+00', null),
  ('00000000-0000-0000-0000-0000000000c1', 'logbook', 2, 25, '2026-03-15 10:00+00', null),
  ('00000000-0000-0000-0000-0000000000c1', 'gate_hopper', 1, 3, '2026-04-01 10:00+00', 'c1000000-0000-7000-8000-000000000001'),
  ('00000000-0000-0000-0000-0000000000c1', 'home_base', null, 5, null, null),
  ('00000000-0000-0000-0000-0000000000c1', 'passport_stamps', 1, 2, '2026-01-01 10:00+00', null);

-- The migration's own statement, run again here on the test rows
update public.user_badges ub
set checkin_id = (
  select c.id from public.checkins c
  where c.user_id = ub.user_id and c.created_at <= ub.unlocked_at
  order by c.created_at desc, c.id desc
  limit 1)
where ub.checkin_id is null and ub.level > 0 and ub.unlocked_at is not null;

select is((select checkin_id from public.user_badges where user_id = '00000000-0000-0000-0000-0000000000c1' and badge_id = 'wheels_up'),
  'c1000000-0000-7000-8000-000000000001'::uuid, 'unlocked together with the first check-in: that one');
select is((select checkin_id from public.user_badges where user_id = '00000000-0000-0000-0000-0000000000c1' and badge_id = 'logbook'),
  'c1000000-0000-7000-8000-000000000002'::uuid, 'unlocked between two check-ins: the newest one before it');
select is((select checkin_id from public.user_badges where user_id = '00000000-0000-0000-0000-0000000000c1' and badge_id = 'gate_hopper'),
  'c1000000-0000-7000-8000-000000000001'::uuid, 'a badge that already had a check-in keeps it');
select is((select checkin_id from public.user_badges where user_id = '00000000-0000-0000-0000-0000000000c1' and badge_id = 'home_base'), null,
  'a badge that is not earned gets nothing');
select is((select checkin_id from public.user_badges where user_id = '00000000-0000-0000-0000-0000000000c1' and badge_id = 'passport_stamps'), null,
  'a badge unlocked before the first check-in existed gets nothing');
select is((select level from public.user_badges where user_id = '00000000-0000-0000-0000-0000000000c1' and badge_id = 'logbook'), 2, 'levels are untouched');

select * from finish();
rollback;
