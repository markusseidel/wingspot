-- Badges and XP: every metric, levels, XP, hidden badges, and that an engine failure never fails an upload.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

-- Country of registration, checked against contracts/test-vectors/registrations.json (37 valid cases)
select is(private.register_country('D-AIMA')::text, 'DE', 'registration D-AIMA is from DE');
select is(private.register_country('D-AIMA')::text, 'DE', 'registration D-AIMA is from DE');
select is(private.register_country('D-AIMA')::text, 'DE', 'registration D-AIMA is from DE');
select is(private.register_country('D-AIMA')::text, 'DE', 'registration D-AIMA is from DE');
select is(private.register_country('N123AB')::text, 'US', 'registration N123AB is from US');
select is(private.register_country('N123AB')::text, 'US', 'registration N123AB is from US');
select is(private.register_country('HB-JNA')::text, 'CH', 'registration HB-JNA is from CH');
select is(private.register_country('G-EUUA')::text, 'GB', 'registration G-EUUA is from GB');
select is(private.register_country('C-FIUA')::text, 'CA', 'registration C-FIUA is from CA');
select is(private.register_country('CS-TJE')::text, 'PT', 'registration CS-TJE is from PT');
select is(private.register_country('JA8089')::text, 'JP', 'registration JA8089 is from JP');
select is(private.register_country('JA8089')::text, 'JP', 'registration JA8089 is from JP');
select is(private.register_country('HL7611')::text, 'KR', 'registration HL7611 is from KR');
select is(private.register_country('B-6497')::text, 'CN', 'registration B-6497 is from CN');
select is(private.register_country('B-HNR')::text, 'HK', 'registration B-HNR is from HK');
select is(private.register_country('B-MAX')::text, 'MO', 'registration B-MAX is from MO');
select is(private.register_country('B-18901')::text, 'TW', 'registration B-18901 is from TW');
select is(private.register_country('9H-AEI')::text, 'MT', 'registration 9H-AEI is from MT');
select is(private.register_country('A6-EOA')::text, 'AE', 'registration A6-EOA is from AE');
select is(private.register_country('VH-OQA')::text, 'AU', 'registration VH-OQA is from AU');
select is(private.register_country('RA-73123')::text, 'RU', 'registration RA-73123 is from RU');
select is(private.register_country('4X-EKA')::text, 'IL', 'registration 4X-EKA is from IL');
select is(private.register_country('PH-BXA')::text, 'NL', 'registration PH-BXA is from NL');
select is(private.register_country('OY-KBA')::text, 'DK', 'registration OY-KBA is from DK');
select is(private.register_country('EC-MXV')::text, 'ES', 'registration EC-MXV is from ES');
select is(private.register_country('F-HPJA')::text, 'FR', 'registration F-HPJA is from FR');
select is(private.register_country('I-ADMA')::text, 'IT', 'registration I-ADMA is from IT');
select is(private.register_country('EI-DEO')::text, 'IE', 'registration EI-DEO is from IE');
select is(private.register_country('OE-LBA')::text, 'AT', 'registration OE-LBA is from AT');
select is(private.register_country('SP-LRA')::text, 'PL', 'registration SP-LRA is from PL');
select is(private.register_country('TC-JJE')::text, 'TR', 'registration TC-JJE is from TR');
select is(private.register_country('ZS-SNA')::text, 'ZA', 'registration ZS-SNA is from ZA');
select is(private.register_country('PR-AXH')::text, 'BR', 'registration PR-AXH is from BR');
select is(private.register_country('9V-SKA')::text, 'SG', 'registration 9V-SKA is from SG');
select is(private.register_country('A7-BAA')::text, 'QA', 'registration A7-BAA is from QA');
select is(private.register_country('VT-ANP')::text, 'IN', 'registration VT-ANP is from IN');
select is(private.register_country('ZK-NZE')::text, 'NZ', 'registration ZK-NZE is from NZ');
select is(private.register_country('XX-ABC')::text, null, 'an unknown prefix has no country');

select is(private.xp_level(0), 1, 'level 1 at 0 XP');
select is(private.xp_level(99), 1, 'still level 1 at 99 XP');
select is(private.xp_level(100), 2, 'level 2 at 100 XP');
select is(private.xp_level(299), 2, 'still level 2 at 299 XP');
select is(private.xp_level(300), 3, 'level 3 at 300 XP');
select is(private.xp_level(600), 4, 'level 4 at 600 XP');

-- Nobody outside the database can call the engine
select is(
  (select count(*)::int from (values
    ('private.register_country(text)'), ('private.xp_level(integer)'), ('private.checkin_facts(uuid)'),
    ('private.badge_values(uuid)'), ('private.evaluate_badges(uuid)')) f(sig)
   where has_function_privilege('authenticated', f.sig, 'execute') or has_function_privilege('anon', f.sig, 'execute')),
  0, 'clients cannot call the engine functions');
select is(has_table_privilege('authenticated', 'public.registration_prefixes', 'select'), false, 'clients cannot read the prefix table');
select is(has_function_privilege('anon', 'public.get_my_progress()', 'execute'), false, 'anonymous visitors cannot read progress');

-- Reference data
insert into public.aircraft_types (icao_code, manufacturer, model, family, engine_type) values
  ('A388', 'Airbus', 'A380-800', 'A380', 'jet'),
  ('B744', 'Boeing', '747-400', '747', 'jet'),
  ('B788', 'Boeing', '787-8', '787', 'jet'),
  ('B772', 'Boeing', '777-200', '777', 'jet'),
  ('B77W', 'Boeing', '777-300ER', '777', 'jet'),
  ('AT76', 'ATR', 'ATR 72-600', 'ATR 72', 'turboprop');
insert into public.airports (id, icao, name, country_code, continent, elevation_ft, location, is_island, min_runway_m) values
  (1, 'EDDF', 'Frankfurt', 'DE', 'EU', 364, 'POINT(8.57 50.03)', false, 4000),
  (2, 'EGLL', 'London Heathrow', 'GB', 'EU', 83, 'POINT(-0.46 51.47)', false, 3600),
  (3, 'KJFK', 'New York JFK', 'US', 'NA', 13, 'POINT(-73.78 40.64)', false, 3400),
  (4, 'ENTC', 'Tromso', 'NO', 'EU', 31, 'POINT(18.92 69.68)', false, 2400),
  (5, 'YSSY', 'Sydney', 'AU', 'OC', 21, 'POINT(151.18 -33.94)', false, 3900),
  (6, 'SLLP', 'La Paz', 'BO', 'SA', 13325, 'POINT(-68.18 -16.51)', false, 4000),
  (7, 'ISL1', 'Tiny Island', 'DE', 'EU', 10, 'POINT(7.5 54.2)', true, 900);

insert into auth.users (id, aud, role, email) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'badges-a@example.test'),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'badges-b@example.test'),
  ('aaaaaaaa-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'badges-c@example.test');
update public.profiles set home_airport = 1, created_at = '2024-03-10 12:00:00+00'
  where id = 'aaaaaaaa-0000-0000-0000-000000000001';

create function pg_temp.spot(uid uuid, reg text, type_code text, airport integer, at timestamptz) returns void
language sql as $$
  insert into public.aircraft (registration, data_status, country_code)
  values (reg, 'user_submitted', private.register_country(reg)) on conflict (registration) do nothing;
  insert into public.checkins (id, user_id, kind, occurred_at, aircraft_id, type_icao, airport_id)
  values (gen_random_uuid(), uid, 'spotted', at, (select id from public.aircraft where registration = reg), type_code, airport);
$$;
create function pg_temp.as_user(uid text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true),
         set_config('role', 'authenticated', true);
$$;
create function pg_temp.levels() returns text language sql as $$
  select coalesce(string_agg(b.id || ':' || ub.level, ',' order by b.position), '')
  from public.user_badges ub join public.badges b on b.id = ub.badge_id
  where ub.user_id = 'aaaaaaaa-0000-0000-0000-000000000001' and ub.level > 0;
$$;

-- Alice's history. Local dates and hours come from each airport's longitude.
select pg_temp.spot('aaaaaaaa-0000-0000-0000-000000000001', 'D-AIMA', 'A388', 1, '2026-01-01 04:30+00');  -- 05:30 local, 1 January
select pg_temp.spot('aaaaaaaa-0000-0000-0000-000000000001', 'D-AIMA', null, 1, '2026-01-02 10:00+00');
select pg_temp.spot('aaaaaaaa-0000-0000-0000-000000000001', 'D-AIMA', null, 1, '2026-01-03 10:00+00');
select pg_temp.spot('aaaaaaaa-0000-0000-0000-000000000001', 'G-EUUU', 'B744', 2, '2026-01-03 22:30+00'); -- 22:30 local
select pg_temp.spot('aaaaaaaa-0000-0000-0000-000000000001', 'N123AB', 'B788', 3, '2026-01-04 15:00+00');
select pg_temp.spot('aaaaaaaa-0000-0000-0000-000000000001', 'VH-OQA', 'B77W', 5, '2026-01-05 20:00+00'); -- 6 January local
select pg_temp.spot('aaaaaaaa-0000-0000-0000-000000000001', 'LN-ABC', 'AT76', 4, '2026-01-10 12:00+00');
select pg_temp.spot('aaaaaaaa-0000-0000-0000-000000000001', 'CP-1234', null, 6, '2026-01-11 12:00+00');
select pg_temp.spot('aaaaaaaa-0000-0000-0000-000000000001', 'D-ADAD', 'B772', 1, '2026-02-14 12:00+00'); -- reads the same backwards
select pg_temp.spot('aaaaaaaa-0000-0000-0000-000000000001', 'D-AIMA', null, 1, '2026-03-10 12:00+00');  -- the day alice joined, two years on
select pg_temp.spot('aaaaaaaa-0000-0000-0000-000000000001', 'JA8089', null, 1, '2026-04-01 12:00+00');  -- a Japanese aircraft in Frankfurt

select is((select value from private.badge_values('aaaaaaaa-0000-0000-0000-000000000001') where badge_id = 'checkins_total'), null, 'there is no badge called checkins_total');
create function pg_temp.v(badge text) returns bigint language sql as $$
  select value from private.badge_values('aaaaaaaa-0000-0000-0000-000000000001') where badge_id = badge;
$$;
select is(pg_temp.v('logbook'), 11::bigint, 'check-ins');
select is(pg_temp.v('fresh_metal'), 8::bigint, 'distinct registrations');
select is(pg_temp.v('old_friend'), 4::bigint, 'the same registration on 4 days');
select is(pg_temp.v('busy_day'), 2::bigint, 'two check-ins on 3 January');
select is(pg_temp.v('daily_spotter'), 4::bigint, 'a streak of 4 days');
select is(pg_temp.v('weekend_warrior'), 2::bigint, 'two weekends in a row');
select is(pg_temp.v('gate_hopper'), 6::bigint, 'distinct airports');
select is(pg_temp.v('home_base'), 6::bigint, 'six check-ins at Frankfurt');
select is(pg_temp.v('home_turf'), 6::bigint, 'check-ins at the home airport');
select is(pg_temp.v('continental'), 4::bigint, 'four continents');
select is(pg_temp.v('high_altitude'), 1::bigint, 'one high airport');
select is(pg_temp.v('arctic_circle'), 1::bigint, 'one airport above the Arctic Circle');
select is(pg_temp.v('southern_cross'), 2::bigint, 'two airports in the south, Sydney and La Paz');
select is(pg_temp.v('passport_stamps'), 6::bigint, 'six airport countries');
select is(pg_temp.v('register_collector'), 7::bigint, 'seven registration countries');
select is(pg_temp.v('far_from_home'), 1::bigint, 'one aircraft outside its own country');
select is(pg_temp.v('home_team'), 2::bigint, 'two German aircraft');
select is(pg_temp.v('neighbourhood_watch'), 2::bigint, 'two registration countries at Frankfurt');
select is(pg_temp.v('global_fleet'), 4::bigint, 'registration continents (Japan has no airport in this data)');
select is(pg_temp.v('type_rater'), 6::bigint, 'distinct types');
select is(pg_temp.v('superjumbo'), 1::bigint, 'A380 family');
select is(pg_temp.v('queen_of_the_skies'), 1::bigint, '747 family');
select is(pg_temp.v('dreamliner'), 1::bigint, '787 family');
select is(pg_temp.v('triple_seven'), 2::bigint, 'two 777 types');
select is(pg_temp.v('airbus_fan'), 1::bigint, 'one Airbus type');
select is(pg_temp.v('boeing_fan'), 4::bigint, 'four Boeing types');
select is(pg_temp.v('prop_power'), 1::bigint, 'one turboprop type');
select is(pg_temp.v('early_bird'), 1::bigint, 'one early check-in');
select is(pg_temp.v('night_owl'), 1::bigint, 'one late check-in');
select is(pg_temp.v('anniversary'), 1::bigint, 'one anniversary');
select is(pg_temp.v('deja_vu'), 4::bigint, 'the same registration at one airport on 4 days');
select is(pg_temp.v('mirror_image'), 1::bigint, 'one palindrome');
select is(pg_temp.v('new_year'), 1::bigint, 'one check-in on 1 January');
select is((select count(*)::int from private.badge_values('aaaaaaaa-0000-0000-0000-000000000001') where badge_id in ('island_hopper', 'short_field')), 0,
          'dormant badges are not evaluated');

-- Levels and XP
select is(jsonb_array_length(private.evaluate_badges('aaaaaaaa-0000-0000-0000-000000000001') -> 'badges_unlocked'), 28, 'first evaluation unlocks 28 badges');
select is(pg_temp.levels(),
  'wheels_up:1,logbook:1,fresh_metal:1,old_friend:2,daily_spotter:1,weekend_warrior:1,gate_hopper:2,home_turf:1,continental:3,high_altitude:1,arctic_circle:1,southern_cross:1,passport_stamps:3,register_collector:2,global_fleet:3,type_rater:2,superjumbo:1,queen_of_the_skies:1,dreamliner:1,triple_seven:1,boeing_fan:1,prop_power:1,early_bird:1,night_owl:1,anniversary:1,deja_vu:1,mirror_image:1,new_year:1',
  'the right levels');
select is(
  (select xp from public.profiles where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  650 + (select sum(50 * level * (level + 1) / 2)::integer from public.user_badges where user_id = 'aaaaaaaa-0000-0000-0000-000000000001' and level > 0),
  'XP is the check-in points plus the badge bonuses');
select is(jsonb_array_length(private.evaluate_badges('aaaaaaaa-0000-0000-0000-000000000001') -> 'badges_unlocked'), 0, 'evaluating again unlocks nothing');
select is(
  (select xp from public.profiles where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  650 + (select sum(50 * level * (level + 1) / 2)::integer from public.user_badges where user_id = 'aaaaaaaa-0000-0000-0000-000000000001' and level > 0),
  'and the XP does not change');

-- Progress for a user with no check-ins: hidden badges stay hidden and dormant ones don't show
select pg_temp.as_user('aaaaaaaa-0000-0000-0000-000000000002');
select is(jsonb_array_length(public.get_my_progress() -> 'badges'), 31, 'a new user sees 31 badges: not the 3 hidden or the 2 dormant');
select is((public.get_my_progress() ->> 'hidden_remaining')::integer, 3, 'and is told 3 hidden ones remain');
select is((public.get_my_progress() ->> 'xp')::integer, 0, 'with no XP');
select is((public.get_my_progress() ->> 'level')::integer, 1, 'at level 1');
select is((select (e ->> 'value')::integer from jsonb_array_elements(public.get_my_progress() -> 'badges') e where e ->> 'id' = 'logbook'), 0, 'logbook progress is 0');
reset role;

-- Alice sees her earned hidden badges
select pg_temp.as_user('aaaaaaaa-0000-0000-0000-000000000001');
select is(jsonb_array_length(public.get_my_progress() -> 'badges'), 34, 'alice sees 31 plus her 3 hidden badges');
select is((public.get_my_progress() ->> 'hidden_remaining')::integer, 0, 'and no hidden ones remain');
reset role;

-- Dormant badges wake up when the data exists, and levels never go down
update public.badges set valid_from = null where id in ('island_hopper', 'short_field');
select pg_temp.spot('aaaaaaaa-0000-0000-0000-000000000001', 'D-AIMA', null, 7, '2026-04-02 12:00+00');
select private.evaluate_badges('aaaaaaaa-0000-0000-0000-000000000001');
select is((select level from public.user_badges where user_id = 'aaaaaaaa-0000-0000-0000-000000000001' and badge_id = 'island_hopper'), 1, 'island hopper unlocks');
select is((select level from public.user_badges where user_id = 'aaaaaaaa-0000-0000-0000-000000000001' and badge_id = 'short_field'), 1, 'short field unlocks');
delete from public.checkins where airport_id = 7;
select private.evaluate_badges('aaaaaaaa-0000-0000-0000-000000000001');
select is((select level from public.user_badges where user_id = 'aaaaaaaa-0000-0000-0000-000000000001' and badge_id = 'island_hopper'), 1, 'a level never goes down');
select is((select progress from public.user_badges where user_id = 'aaaaaaaa-0000-0000-0000-000000000001' and badge_id = 'island_hopper'), 0, 'while progress follows the data');

-- Uploading returns badges, XP and level
select pg_temp.as_user('aaaaaaaa-0000-0000-0000-000000000003');
select is(
  public.sync_checkins('[{"id":"30000000-0000-0000-0000-000000000001","kind":"spotted","occurred_at":"2026-05-01T10:00:00Z","registration":"D-NEWAA","airport_id":1}]'::jsonb) #>> '{badges_unlocked,0,id}',
  'wheels_up', 'an upload reports the badge it unlocked');
select is(
  (public.sync_checkins('[{"id":"30000000-0000-0000-0000-000000000001","kind":"spotted","occurred_at":"2026-05-01T10:00:00Z","registration":"D-NEWAA","airport_id":1}]'::jsonb) ->> 'xp')::integer,
  115, 'with 10 + 15 + 40 XP and 50 for the badge');
select is(
  jsonb_array_length(public.sync_checkins('[{"id":"30000000-0000-0000-0000-000000000001","kind":"spotted","occurred_at":"2026-05-01T10:00:00Z","registration":"D-NEWAA","airport_id":1}]'::jsonb) -> 'badges_unlocked'),
  0, 'repeating the upload unlocks nothing new, which is why the app must not rely on this answer alone');
reset role;

-- A broken engine never fails an upload
create or replace function private.badge_values(uid uuid) returns table (badge_id text, value bigint)
language plpgsql as $$ begin raise exception 'boom'; end; $$;
select pg_temp.as_user('aaaaaaaa-0000-0000-0000-000000000003');
select is(
  public.sync_checkins('[{"id":"30000000-0000-0000-0000-000000000002","kind":"spotted","occurred_at":"2026-05-02T10:00:00Z","registration":"D-NEWBB"}]'::jsonb),
  '{"results":[{"id":"30000000-0000-0000-0000-000000000002","status":"stored"}]}'::jsonb,
  'the check-in is stored and the answer has no badge data');
select is(
  (select count(*)::int from public.checkins where id = '30000000-0000-0000-0000-000000000002'), 1,
  'and the row exists');
reset role;

select * from finish();
rollback;
