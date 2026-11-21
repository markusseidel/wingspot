-- Badges for spotting locations and sessions. Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

insert into auth.users (id, aud, role, email) values
  ('00000000-0000-0000-0000-000000001101', 'authenticated', 'authenticated', 'sb1@example.test'),
  ('00000000-0000-0000-0000-000000001102', 'authenticated', 'authenticated', 'sb2@example.test');
-- Longitude 8 is one hour ahead of UTC in the estimate of local time
insert into public.airports (id, icao, iata, name, country_code, continent, location) values
  (899001, 'ZZBA', 'ZBA', 'Badge spot airport', 'DE', 'EU', 'POINT(8 50)');
insert into public.spotting_locations (id, airport_id, name, location, status, created_by) values
  (899100, 899001, 'Own place', 'POINT(8.001 50.001)', 'approved', '00000000-0000-0000-0000-000000001101'),
  (899101, 899001, 'Other place', 'POINT(8.002 50.002)', 'approved', '00000000-0000-0000-0000-000000001102'),
  (899102, 899001, 'Waiting place', 'POINT(8.003 50.003)', 'pending', '00000000-0000-0000-0000-000000001101');

-- Three visits at places: 05:30 local (morning), 12:00 local, 18:30 local (evening)
insert into public.checkins (id, user_id, kind, occurred_at, airport_id, visit_context, spot_location_id, visibility) values
  ('e9000000-0000-7000-8000-000000000001', '00000000-0000-0000-0000-000000001101', 'airport', '2026-03-01T04:30:00Z', 899001, 'spotting', 899100, 'public'),
  ('e9000000-0000-7000-8000-000000000002', '00000000-0000-0000-0000-000000001101', 'airport', '2026-03-02T11:00:00Z', 899001, 'spotting', 899100, 'public'),
  ('e9000000-0000-7000-8000-000000000003', '00000000-0000-0000-0000-000000001101', 'airport', '2026-03-03T17:30:00Z', 899001, 'spotting', 899101, 'public'),
  ('e9000000-0000-7000-8000-000000000004', '00000000-0000-0000-0000-000000001101', 'airport', '2026-03-04T10:00:00Z', 899001, 'spotting', null, 'public');
-- Three sightings in the first session, one in the third, one without a session
insert into public.checkins (id, user_id, kind, occurred_at, type_icao, airport_id, visit_id, visibility)
select ('e9000000-0000-7000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid, '00000000-0000-0000-0000-000000001101', 'spotted',
       '2026-03-01T05:00:00Z'::timestamptz + n * interval '1 minute', null, 899001, v.visit, 'public'
from (values (1, 'e9000000-0000-7000-8000-000000000001'::uuid), (2, 'e9000000-0000-7000-8000-000000000001'::uuid),
             (3, 'e9000000-0000-7000-8000-000000000001'::uuid), (4, 'e9000000-0000-7000-8000-000000000003'::uuid),
             (5, null)) v(n, visit);

create function pg_temp.value(badge text) returns bigint language sql as $$
  select value from private.badge_values('00000000-0000-0000-0000-000000001101') where badge_id = badge;
$$;

select is(pg_temp.value('first_spot_session'), 3::bigint, 'visits at a spotting location are counted, one without a place is not');
select is(pg_temp.value('deck_regular'), 2::bigint, 'the most visits at one place');
select is(pg_temp.value('place_collector'), 2::bigint, 'different places');
select is(pg_temp.value('session_pro'), 3::bigint, 'the most sightings in one session');
select is(pg_temp.value('cartographer'), 1::bigint, 'only an approved place of your own counts');
select is(pg_temp.value('sunrise_hunter'), 2::bigint, 'sessions begun in the early morning or the evening');

-- Someone else's visits and places do not count for the first user, and the other user has nothing of their own
select is((select value from private.badge_values('00000000-0000-0000-0000-000000001102') where badge_id = 'first_spot_session'), 0::bigint, 'another person starts at zero');
select is((select value from private.badge_values('00000000-0000-0000-0000-000000001102') where badge_id = 'cartographer'), 1::bigint, 'and has their own approved place');

-- The first user earns the badges through the normal evaluation
select private.evaluate_badges('00000000-0000-0000-0000-000000001101');
select is((select level from public.user_badges where user_id = '00000000-0000-0000-0000-000000001101' and badge_id = 'deck_regular'), null, 'two visits are not yet the first level of Deck Regular');
select is((select level from public.user_badges where user_id = '00000000-0000-0000-0000-000000001101' and badge_id = 'first_spot_session'), 1, 'First Session is earned');
select is((select level from public.user_badges where user_id = '00000000-0000-0000-0000-000000001101' and badge_id = 'sunrise_hunter'), 1, 'Sunrise Hunter level 1');

select finish();
rollback;
