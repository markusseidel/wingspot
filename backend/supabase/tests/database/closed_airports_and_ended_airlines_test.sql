-- Closed airports and airlines that no longer fly: the data, and the two metrics that count them.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

-- Badge definitions are not in the repository (see backend/private/README.md), so the test makes its own.
delete from public.user_badges where badge_id in (select id from public.badges where hidden);
delete from public.badges where hidden;
insert into public.badges (id, name, description, category, kind, rule, levels, hidden, valid_from, position) values
  ('test_hidden_closed', '{"en": "Test closed"}'::jsonb, '{"en": "Test"}'::jsonb, 'hidden', 'leveled', '{"metric": "airports_closed"}'::jsonb, '{1,2}', true, null, 41),
  ('test_hidden_ended', '{"en": "Test ended"}'::jsonb, '{"en": "Test"}'::jsonb, 'hidden', 'leveled', '{"metric": "operators_ceased"}'::jsonb, '{1,2}', true, null, 42);

-- The data
select is((select closed_on from public.airports where icao = 'EDDT'), date '2020-11-08', 'Berlin Tegel is in the data, as closed');
select is((select iata from public.airports where icao = 'EDDT'), 'TXL', 'with its IATA code');
select is((select ceased_on from public.operators where icao = 'BER'), date '2017-10-27', 'Air Berlin is in the data, as ended');
select is((select iata from public.operators where icao = 'BER'), 'AB', 'with its IATA code');

insert into auth.users (id, aud, role, email) values
  ('00000000-0000-0000-0000-000000000e01', 'authenticated', 'authenticated', 'closed@example.test');
insert into public.airports (id, icao, iata, name, country_code, continent, location) values
  (894001, 'ZZZK', 'ZZK', 'Open airport A', 'DE', 'EU', 'POINT(8 50)'),
  (894002, 'ZZZL', 'ZZL', 'Open airport B', 'DE', 'EU', 'POINT(9 51)');
insert into public.airports (id, icao, iata, name, country_code, continent, location, closed_on) values
  (894003, 'ZZZM', 'ZZM', 'Closed airport', 'DE', 'EU', 'POINT(10 52)', '2019-01-01');
create function pg_temp.fly(origin integer, destination integer, number text, at timestamptz) returns void language sql as $$
  insert into public.checkins (id, user_id, kind, occurred_at, visibility, origin_id, destination_id, flight_number)
  values (gen_random_uuid(), '00000000-0000-0000-0000-000000000e01', 'flown', at, 'private', origin, destination, number);
$$;
create function pg_temp.value(badge text) returns bigint language sql as $$
  select value from private.badge_values('00000000-0000-0000-0000-000000000e01') where badge_id = badge;
$$;

-- Closed airports
select pg_temp.fly(894001, 894002, null, '2018-05-01');
select is(pg_temp.value('test_hidden_closed'), 0::bigint, 'flights between open airports count nothing');
select pg_temp.fly(894001, 894003, null, '2018-06-01');
select is(pg_temp.value('test_hidden_closed'), 1::bigint, 'a flight to a closed airport counts it');
select pg_temp.fly(894003, 894002, null, '2018-07-01');
select is(pg_temp.value('test_hidden_closed'), 1::bigint, 'the same closed airport again counts once');
insert into public.checkins (id, user_id, kind, occurred_at, visibility, airport_id, visit_context)
  values (gen_random_uuid(), '00000000-0000-0000-0000-000000000e01', 'airport', '2019-01-01', 'private', 9000001, 'spotting');
select is(pg_temp.value('test_hidden_closed'), 2::bigint, 'a visit counts too, and another closed airport adds one');

-- Airlines that no longer fly
select is(pg_temp.value('test_hidden_ended'), 0::bigint, 'nothing yet');
select pg_temp.fly(894001, 894002, 'LH400', '2016-03-01');
select is(pg_temp.value('test_hidden_ended'), 0::bigint, 'an airline that still flies does not count');
select pg_temp.fly(894001, 894002, 'AB 6123', '2016-03-01');
select is(pg_temp.value('test_hidden_ended'), 1::bigint, 'AB with a space and digits is Air Berlin, flown before it stopped');
select pg_temp.fly(894001, 894002, 'ab6124', '2016-03-02');
select is(pg_temp.value('test_hidden_ended'), 1::bigint, 'lower case and the same airline again counts once');
select pg_temp.fly(894001, 894002, 'BER7001', '2017-01-01');
select is(pg_temp.value('test_hidden_ended'), 1::bigint, 'the ICAO code is the same airline');
select pg_temp.fly(894001, 894002, 'AB1234', '2024-01-01');
select is(pg_temp.value('test_hidden_ended'), 1::bigint, 'a flight after the airline stopped does not count, the code may belong to another one now');
select pg_temp.fly(894001, 894002, 'ABX5', '2016-03-03');
select is(pg_temp.value('test_hidden_ended'), 1::bigint, 'a longer code that merely starts with AB does not count');
select pg_temp.fly(894001, 894002, 'HG2001', '2017-12-01');
select is(pg_temp.value('test_hidden_ended'), 2::bigint, 'a second airline that stopped adds one');

select private.evaluate_badges('00000000-0000-0000-0000-000000000e01');
select is((select string_agg(badge_id || ':' || level, ',' order by badge_id) from public.user_badges
  where user_id = '00000000-0000-0000-0000-000000000e01' and level > 0 and badge_id like 'test_hidden_%'), 'test_hidden_closed:2,test_hidden_ended:2',
  'the badges are earned');

select * from finish();
rollback;
