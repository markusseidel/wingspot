-- Distance badges: three single-level badges on the total distance of the flights (6,372 km, 40,076 km and 384,401 km).
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

-- Hidden badges are not in the repository (see backend/private/README.md), so this test makes its own. The ones a
-- database may already have are removed for the length of the test.
delete from public.user_badges where badge_id in (select id from public.badges where hidden);
delete from public.badges where hidden;
insert into public.badges (id, name, description, category, kind, rule, levels, hidden, valid_from, position) values
  ('test_distance_1', '{"en": "Test distance 1"}'::jsonb, '{"en": "Test"}'::jsonb, 'hidden', 'single', '{"metric": "distance_flown_km"}'::jsonb, '{6372}', true, null, 37),
  ('test_distance_2', '{"en": "Test distance 2"}'::jsonb, '{"en": "Test"}'::jsonb, 'hidden', 'single', '{"metric": "distance_flown_km"}'::jsonb, '{40076}', true, null, 38),
  ('test_distance_3', '{"en": "Test distance 3"}'::jsonb, '{"en": "Test"}'::jsonb, 'hidden', 'single', '{"metric": "distance_flown_km"}'::jsonb, '{384401}', true, null, 39);

insert into auth.users (id, aud, role, email) values
  ('00000000-0000-0000-0000-000000000a01', 'authenticated', 'authenticated', 'distance@example.test');
insert into public.airports (id, icao, iata, name, country_code, continent, location) values
  (891001, 'ZZZC', 'ZZC', 'Distance test A', 'DE', 'EU', 'POINT(8 50)'),
  (891002, 'ZZZD', 'ZZD', 'Distance test B', 'DE', 'EU', 'POINT(9 51)');
create function pg_temp.flight(km integer, other uuid default '00000000-0000-0000-0000-000000000a01') returns void language sql as $$
  insert into public.checkins (id, user_id, kind, occurred_at, visibility, origin_id, destination_id, distance_km)
  values (gen_random_uuid(), other, 'flown', now(), 'private', 891001, 891002, km);
$$;
create function pg_temp.earned() returns text language sql as $$
  select coalesce(string_agg(badge_id, ',' order by badge_id), '') from public.user_badges
  where user_id = '00000000-0000-0000-0000-000000000a01' and level > 0
    and badge_id in ('test_distance_1', 'test_distance_2', 'test_distance_3');
$$;

select pg_temp.flight(3000);
select pg_temp.flight(3371);
select private.evaluate_badges('00000000-0000-0000-0000-000000000a01');
select is(pg_temp.earned(), '', 'exactly 6,371 km is not enough');
select pg_temp.flight(1);
select private.evaluate_badges('00000000-0000-0000-0000-000000000a01');
select is(pg_temp.earned(), 'test_distance_1', 'over 6,371 km earns the first');
select pg_temp.flight(33704);
select private.evaluate_badges('00000000-0000-0000-0000-000000000a01');
select is(pg_temp.earned(), 'test_distance_1,test_distance_2', 'over 40,075 km earns the second');
select pg_temp.flight(344325);
select private.evaluate_badges('00000000-0000-0000-0000-000000000a01');
select is(pg_temp.earned(), 'test_distance_1,test_distance_2,test_distance_3', 'over 384,400 km earns the third');

select is((select count(*)::int from public.badges where id in ('test_distance_1', 'test_distance_2', 'test_distance_3') and hidden), 3,
          'all three are hidden');
select * from finish();
rollback;
