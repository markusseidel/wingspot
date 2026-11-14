-- The three hidden distance badges: the radius of the Earth, its circumference and the distance to the Moon.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

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
    and badge_id in ('earth_radius', 'earth_circumference', 'to_the_moon');
$$;

select pg_temp.flight(3000);
select pg_temp.flight(3371);
select private.evaluate_badges('00000000-0000-0000-0000-000000000a01');
select is(pg_temp.earned(), '', 'exactly the radius of the Earth is not more than the radius');
select pg_temp.flight(1);
select private.evaluate_badges('00000000-0000-0000-0000-000000000a01');
select is(pg_temp.earned(), 'earth_radius', 'over 6,371 km earns the first badge');
select pg_temp.flight(33704);
select private.evaluate_badges('00000000-0000-0000-0000-000000000a01');
select is(pg_temp.earned(), 'earth_circumference,earth_radius', 'over 40,075 km earns the second');
select pg_temp.flight(344325);
select private.evaluate_badges('00000000-0000-0000-0000-000000000a01');
select is(pg_temp.earned(), 'earth_circumference,earth_radius,to_the_moon', 'over 384,400 km earns the Moon');

select is((select count(*)::int from public.badges where id in ('earth_radius', 'earth_circumference', 'to_the_moon') and hidden), 3,
          'all three are hidden');
select * from finish();
rollback;
