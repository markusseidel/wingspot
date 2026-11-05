-- Badges and XP (docs/BADGES.md, docs/PHASE1.md milestone 4).
--
-- Badges are data: a rule (a metric and its parameters), levels, and text in each language.
-- One function computes every metric for a user from their check-ins, a second one stores new
-- levels and recomputes XP. Both are safe to repeat, and levels never go down.
--
-- The engine runs at the end of sync_checkins and from get_my_progress. A failure in the engine
-- never fails an upload: check-ins are stored first, so the phone's retry logic stays simple.

-- Text per language, and a fixed order for the app --------------------------------------------
alter table public.badges alter column name type jsonb using jsonb_build_object('en', name);
alter table public.badges alter column description type jsonb
  using case when description is null then null else jsonb_build_object('en', description) end;
alter table public.badges add constraint badges_name_has_english check (name ? 'en');
alter table public.badges alter column category set not null;
alter table public.badges alter column kind set not null;
alter table public.badges alter column levels set not null;
alter table public.badges add constraint badges_have_levels check (cardinality(levels) >= 1);
alter table public.badges add column position integer not null default 0;

-- Country of registration --------------------------------------------------------------------
-- From the same prefix list as the apps (ios/Packages/WingspotCore NationalityPrefix.swift), checked
-- against contracts/test-vectors/registrations.json by the database tests.
create table public.registration_prefixes (
  prefix       text primary key,
  country_code char(2) not null,
  uses_dash    boolean not null
);
alter table public.registration_prefixes enable row level security;

insert into public.registration_prefixes (prefix, country_code, uses_dash) values
  ('B', 'CN', true),
  ('C', 'CA', true),
  ('D', 'DE', true),
  ('F', 'FR', true),
  ('G', 'GB', true),
  ('I', 'IT', true),
  ('M', 'IM', true),
  ('N', 'US', false),
  ('A2', 'BW', true),
  ('A3', 'TO', true),
  ('A5', 'BT', true),
  ('A6', 'AE', true),
  ('A7', 'QA', true),
  ('AP', 'PK', true),
  ('CC', 'CL', true),
  ('CN', 'MA', true),
  ('CP', 'BO', true),
  ('CS', 'PT', true),
  ('CU', 'CU', true),
  ('CX', 'UY', true),
  ('C5', 'GM', true),
  ('C6', 'BS', true),
  ('C9', 'MZ', true),
  ('D2', 'AO', true),
  ('D4', 'CV', true),
  ('EC', 'ES', true),
  ('EI', 'IE', true),
  ('EK', 'AM', true),
  ('EP', 'IR', true),
  ('ER', 'MD', true),
  ('ES', 'EE', true),
  ('ET', 'ET', true),
  ('EW', 'BY', true),
  ('EX', 'KG', true),
  ('EY', 'TJ', true),
  ('EZ', 'TM', true),
  ('HA', 'HU', true),
  ('HB', 'CH', true),
  ('HC', 'EC', true),
  ('HH', 'HT', true),
  ('HI', 'DO', true),
  ('HK', 'CO', true),
  ('HL', 'KR', false),
  ('HP', 'PA', true),
  ('HR', 'HN', true),
  ('HS', 'TH', true),
  ('HZ', 'SA', true),
  ('JA', 'JP', false),
  ('JY', 'JO', true),
  ('LN', 'NO', true),
  ('LV', 'AR', true),
  ('LX', 'LU', true),
  ('LY', 'LT', true),
  ('LZ', 'BG', true),
  ('OB', 'PE', true),
  ('OD', 'LB', true),
  ('OE', 'AT', true),
  ('OH', 'FI', true),
  ('OK', 'CZ', true),
  ('OM', 'SK', true),
  ('OO', 'BE', true),
  ('OY', 'DK', true),
  ('PH', 'NL', true),
  ('PK', 'ID', true),
  ('PP', 'BR', true),
  ('PR', 'BR', true),
  ('PS', 'BR', true),
  ('PT', 'BR', true),
  ('PU', 'BR', true),
  ('PZ', 'SR', true),
  ('RA', 'RU', true),
  ('RP', 'PH', true),
  ('SE', 'SE', true),
  ('SP', 'PL', true),
  ('ST', 'SD', true),
  ('SU', 'EG', true),
  ('SX', 'GR', true),
  ('S2', 'BD', true),
  ('S5', 'SI', true),
  ('S7', 'SC', true),
  ('TC', 'TR', true),
  ('TF', 'IS', true),
  ('TG', 'GT', true),
  ('TI', 'CR', true),
  ('TS', 'TN', true),
  ('T7', 'SM', true),
  ('UK', 'UZ', true),
  ('UN', 'KZ', true),
  ('UP', 'KZ', true),
  ('UR', 'UA', true),
  ('VH', 'AU', true),
  ('VN', 'VN', true),
  ('VT', 'IN', true),
  ('XA', 'MX', true),
  ('XB', 'MX', true),
  ('XC', 'MX', true),
  ('XU', 'KH', true),
  ('XY', 'MM', true),
  ('YA', 'AF', true),
  ('YI', 'IQ', true),
  ('YK', 'SY', true),
  ('YL', 'LV', true),
  ('YR', 'RO', true),
  ('YS', 'SV', true),
  ('YU', 'RS', true),
  ('YV', 'VE', true),
  ('ZA', 'AL', true),
  ('ZK', 'NZ', true),
  ('ZP', 'PY', true),
  ('ZS', 'ZA', true),
  ('Z3', 'MK', true),
  ('3A', 'MC', true),
  ('3B', 'MU', true),
  ('4K', 'AZ', true),
  ('4L', 'GE', true),
  ('4O', 'ME', true),
  ('4R', 'LK', true),
  ('4X', 'IL', true),
  ('5A', 'LY', true),
  ('5B', 'CY', true),
  ('5H', 'TZ', true),
  ('5N', 'NG', true),
  ('5R', 'MG', true),
  ('5T', 'MR', true),
  ('5U', 'NE', true),
  ('5X', 'UG', true),
  ('5Y', 'KE', true),
  ('6O', 'SO', true),
  ('6V', 'SN', true),
  ('6Y', 'JM', true),
  ('7O', 'YE', true),
  ('7P', 'LS', true),
  ('7Q', 'MW', true),
  ('7T', 'DZ', true),
  ('8P', 'BB', true),
  ('8Q', 'MV', true),
  ('8R', 'GY', true),
  ('9A', 'HR', true),
  ('9G', 'GH', true),
  ('9H', 'MT', true),
  ('9J', 'ZM', true),
  ('9K', 'KW', true),
  ('9L', 'SL', true),
  ('9M', 'MY', true),
  ('9N', 'NP', true),
  ('9Q', 'CD', true),
  ('9V', 'SG', true),
  ('9Y', 'TT', true);

alter table public.aircraft add column country_code char(2);
create index airports_country_code_idx on public.airports (country_code);

create function private.register_country(reg text) returns char(2)
language plpgsql stable set search_path = '' as $$
declare
  dash integer := position('-' in reg);
  v_prefix text;
  v_mark text;
  v_country char(2);
begin
  if dash > 0 then
    v_prefix := substr(reg, 1, dash - 1);
    v_mark := substr(reg, dash + 1);
    select p.country_code into v_country
    from public.registration_prefixes p where p.prefix = v_prefix and p.uses_dash;
  else
    -- Registers that write no dash: N, JA, HL.
    select p.prefix, p.country_code into v_prefix, v_country
    from public.registration_prefixes p
    where not p.uses_dash and reg like p.prefix || '%'
    order by length(p.prefix) desc limit 1;
    v_mark := substr(reg, coalesce(length(v_prefix), 0) + 1);
  end if;
  if v_country is null then
    return null;
  end if;
  if v_prefix = 'B' then
    -- B is shared by China, Hong Kong, Macau and Taiwan.
    return case
      when substr(v_mark, 1, 1) in ('H', 'K', 'L') then 'HK'
      when substr(v_mark, 1, 1) = 'M' then 'MO'
      when length(v_mark) = 5 and v_mark ~ '^[0-9]+$' then 'TW'
      else 'CN'
    end;
  end if;
  return v_country;
end;
$$;

update public.aircraft set country_code = private.register_country(registration);

-- XP level: level L starts at 50 * L * (L - 1) XP, so 0, 100, 300, 600, 1000 ...
create function private.xp_level(xp integer) returns integer
language sql immutable set search_path = '' as $$
  select floor((1 + sqrt(1 + greatest(xp, 0) / 12.5)) / 2)::integer;
$$;

-- What a user has done, one row per spotted check-in, with everything the metrics need ----------
-- "Local time" is estimated from the airport's longitude (or the stored position when there is no
-- airport), because the airport data has no time zones.
create function private.checkin_facts(uid uuid) returns table (
  checkin_id uuid, aircraft_id integer, registration text, reg_country text, type_icao text,
  family text, manufacturer text, engine_type text, airport_id integer, airport_country text,
  airport_continent text, is_island boolean, min_runway_m integer, elevation_ft integer,
  airport_lat double precision, local_ts timestamp
)
language sql stable security definer set search_path = '' as $$
  select c.id, c.aircraft_id, a.registration, a.country_code::text, c.type_icao,
         t.family, t.manufacturer, t.engine_type, c.airport_id, ap.country_code::text,
         ap.continent::text, ap.is_island, ap.min_runway_m, ap.elevation_ft,
         extensions.st_y(ap.location::extensions.geometry),
         (c.occurred_at at time zone 'UTC') + make_interval(hours => round(
           coalesce(extensions.st_x(ap.location::extensions.geometry),
                    extensions.st_x(c.location::extensions.geometry), 0) / 15)::integer)
  from public.checkins c
  left join public.aircraft a on a.id = c.aircraft_id
  left join public.aircraft_types t on t.icao_code = c.type_icao
  left join public.airports ap on ap.id = c.airport_id
  where c.user_id = uid and c.kind = 'spotted';
$$;

-- The current value of every active badge's metric for a user ---------------------------------
create function private.badge_values(uid uuid) returns table (badge_id text, value bigint)
language sql stable security definer set search_path = '' as $$
  with f as materialized (select * from private.checkin_facts(uid)),
  prof as (select p.home_airport, p.created_at at time zone 'UTC' as joined from public.profiles p where p.id = uid),
  home as (select ap.country_code::text as cc from public.airports ap where ap.id = (select home_airport from prof)),
  days as (select distinct local_ts::date as d from f),
  day_groups as (select d, d - (row_number() over (order by d))::integer as g from days),
  weekends as (
    select distinct ((date_trunc('week', local_ts)::date - date '2000-01-03') / 7) as n
    from f where extract(isodow from local_ts) in (6, 7)
  ),
  weekend_groups as (select n, n - row_number() over (order by n) as g from weekends),
  country_continent as (
    select s.cc,
           (select mode() within group (order by ap.continent) from public.airports ap where ap.country_code = s.cc) as cont
    from (select distinct reg_country::char(2) as cc from f where reg_country is not null) s
  )
  select b.id,
    coalesce(case b.rule ->> 'metric'
      when 'checkins_total' then (select count(*) from f)
      when 'registrations_distinct' then (select count(distinct aircraft_id) from f)
      when 'same_registration_days' then (
        select max(n) from (select count(distinct local_ts::date) as n from f where aircraft_id is not null group by aircraft_id) s)
      when 'checkins_in_one_day' then (
        select max(n) from (select count(*) as n from f group by local_ts::date) s)
      when 'streak_days' then (select max(len) from (select count(*) as len from day_groups group by g) s)
      when 'streak_weekends' then (select max(len) from (select count(*) as len from weekend_groups group by g) s)
      when 'airports_distinct' then (select count(distinct airport_id) from f)
      when 'airport_repeat_max' then (
        select max(n) from (select count(*) as n from f where airport_id is not null group by airport_id) s)
      when 'home_airport_checkin' then (
        select count(*) from f where airport_id is not null and airport_id = (select home_airport from prof))
      when 'continents_distinct' then (select count(distinct airport_continent) from f)
      when 'airports_where' then (
        select count(distinct airport_id) from f
        where coalesce(case b.rule ->> 'where'
          when 'island' then is_island
          when 'short_runway' then min_runway_m < 1000
          when 'high_altitude' then elevation_ft > 8202
          when 'arctic' then airport_lat > 66.5
          when 'southern' then airport_lat < 0
        end, false))
      when 'airport_countries_distinct' then (select count(distinct airport_country) from f)
      when 'register_countries_distinct' then (select count(distinct reg_country) from f)
      when 'far_from_home' then (
        select count(distinct aircraft_id) from f
        where reg_country is not null and airport_country is not null and reg_country <> airport_country)
      when 'home_team' then (
        select count(distinct aircraft_id) from f where reg_country is not null and reg_country = (select cc from home))
      when 'register_countries_at_airport_max' then (
        select max(n) from (select count(distinct reg_country) as n from f where airport_id is not null group by airport_id) s)
      when 'register_continents_distinct' then (select count(distinct cont) from country_continent)
      when 'types_distinct' then (select count(distinct type_icao) from f)
      when 'types_in_family' then (select count(distinct type_icao) from f where family = b.rule ->> 'family')
      when 'types_by_manufacturer' then (select count(distinct type_icao) from f where manufacturer = b.rule ->> 'manufacturer')
      when 'types_by_engine' then (select count(distinct type_icao) from f where engine_type = b.rule ->> 'engine_type')
      when 'local_hour_between' then (
        select count(*) from f
        where case when (b.rule ->> 'start')::integer <= (b.rule ->> 'end')::integer
          then extract(hour from local_ts) >= (b.rule ->> 'start')::integer and extract(hour from local_ts) < (b.rule ->> 'end')::integer
          else extract(hour from local_ts) >= (b.rule ->> 'start')::integer or extract(hour from local_ts) < (b.rule ->> 'end')::integer
        end)
      when 'anniversary' then (
        select count(distinct extract(year from f.local_ts)) from f cross join prof
        where extract(year from f.local_ts) > extract(year from prof.joined)
          and extract(month from f.local_ts) = extract(month from prof.joined)
          and extract(day from f.local_ts) = extract(day from prof.joined))
      when 'same_registration_airport_days' then (
        select max(n) from (
          select count(distinct local_ts::date) as n from f
          where aircraft_id is not null and airport_id is not null group by aircraft_id, airport_id) s)
      when 'palindrome_registrations' then (
        select count(distinct aircraft_id) from f
        where length(replace(registration, '-', '')) >= 4
          and replace(registration, '-', '') = reverse(replace(registration, '-', '')))
      when 'checkins_on_date' then (
        select count(*) from f
        where extract(month from local_ts) = (b.rule ->> 'month')::integer
          and extract(day from local_ts) = (b.rule ->> 'day')::integer)
    end, 0)::bigint
  from public.badges b
  where (b.valid_from is null or b.valid_from <= now()) and (b.valid_until is null or b.valid_until > now());
$$;

-- Stores new badge levels, recomputes XP, and says what was unlocked ---------------------------
create function private.evaluate_badges(uid uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  r record;
  old_level integer;
  unlocked jsonb := '[]'::jsonb;
  new_xp integer;
begin
  for r in
    select b.id, b.name, b.description, b.category, b.kind, v.value,
           (select count(*) from unnest(b.levels) as l where v.value >= l)::integer as new_level
    from private.badge_values(uid) v
    join public.badges b on b.id = v.badge_id
    order by b.position
  loop
    select coalesce(ub.level, 0) into old_level
    from public.user_badges ub where ub.user_id = uid and ub.badge_id = r.id;
    old_level := coalesce(old_level, 0);

    -- A level never goes down, even if the data behind it changes.
    insert into public.user_badges (user_id, badge_id, level, progress, unlocked_at)
    values (uid, r.id, nullif(greatest(old_level, r.new_level), 0), r.value::integer,
            case when r.new_level > old_level then now() end)
    on conflict (user_id, badge_id) do update
      set progress = excluded.progress,
          level = excluded.level,
          unlocked_at = coalesce(excluded.unlocked_at, public.user_badges.unlocked_at);

    if r.new_level > old_level then
      unlocked := unlocked || jsonb_build_object(
        'id', r.id, 'level', r.new_level, 'previous_level', old_level,
        'name', r.name, 'description', r.description, 'category', r.category, 'kind', r.kind);
    end if;
  end loop;

  -- XP is a function of the data, so repeating this never double counts.
  select (10 * count(*) + 15 * count(distinct aircraft_id) + 30 * count(distinct type_icao)
          + 40 * count(distinct airport_id))::integer
  into new_xp
  from private.checkin_facts(uid);
  new_xp := new_xp + coalesce((
    select sum(50 * ub.level * (ub.level + 1) / 2)::integer
    from public.user_badges ub where ub.user_id = uid and ub.level is not null), 0);
  update public.profiles set xp = new_xp where id = uid;

  return jsonb_build_object('badges_unlocked', unlocked, 'xp', new_xp, 'level', private.xp_level(new_xp));
end;
$$;

-- The signed-in user's progress. Also catches up on badges for check-ins uploaded before this existed.
create function public.get_my_progress() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  my_xp integer;
  my_level integer;
  listed jsonb;
  hidden_left integer;
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  begin
    perform private.evaluate_badges(uid);
  exception when others then
    raise warning 'badge evaluation failed: %', sqlerrm;
  end;

  select p.xp into my_xp from public.profiles p where p.id = uid;
  my_level := private.xp_level(my_xp);

  -- Hidden badges stay out of the list until earned, and dormant ones (no data yet) never show.
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', b.id, 'name', b.name, 'description', b.description, 'category', b.category,
           'kind', b.kind, 'hidden', b.hidden, 'levels', to_jsonb(b.levels),
           'value', coalesce(ub.progress, 0), 'level', coalesce(ub.level, 0),
           'unlocked_at', ub.unlocked_at) order by b.position), '[]'::jsonb),
         count(*) filter (where b.hidden and coalesce(ub.level, 0) = 0)::integer
  into listed, hidden_left
  from public.badges b
  left join public.user_badges ub on ub.badge_id = b.id and ub.user_id = uid
  where (b.valid_from is null or b.valid_from <= now()) and (b.valid_until is null or b.valid_until > now());

  return jsonb_build_object(
    'xp', my_xp, 'level', my_level,
    'xp_for_level', 50 * my_level * (my_level - 1),
    'xp_for_next_level', 50 * (my_level + 1) * my_level,
    'badges', (select coalesce(jsonb_agg(e), '[]'::jsonb) from jsonb_array_elements(listed) e
               where not (e ->> 'hidden')::boolean or (e ->> 'level')::integer > 0),
    'hidden_remaining', hidden_left);
end;
$$;

revoke execute on function private.register_country(text), private.xp_level(integer),
  private.checkin_facts(uuid), private.badge_values(uuid), private.evaluate_badges(uuid)
  from public, anon, authenticated;
revoke execute on function public.get_my_progress() from public;
grant execute on function public.get_my_progress() to authenticated;

-- The badges ------------------------------------------------------------------------------------
-- Dormant badges have valid_from = infinity until the data behind them exists: island_hopper needs
-- the island flag and short_field needs runway lengths, and neither is filled in yet.
insert into public.badges (id, name, description, category, kind, rule, levels, hidden, valid_from, position) values
  ('wheels_up', '{"en": "Wheels Up", "de": "Abheben"}'::jsonb, '{"en": "Make your first check-in.", "de": "Mache deinen ersten Check-in."}'::jsonb, 'milestones', 'single', '{"metric": "checkins_total"}'::jsonb, '{1}', false, null, 1),
  ('logbook', '{"en": "Logbook", "de": "Logbuch"}'::jsonb, '{"en": "Keep your logbook growing: total check-ins.", "de": "Lass dein Logbuch wachsen: Check-ins insgesamt."}'::jsonb, 'milestones', 'leveled', '{"metric": "checkins_total"}'::jsonb, '{10,25,50,100,250,500,1000}', false, null, 2),
  ('fresh_metal', '{"en": "Fresh Metal", "de": "Frisches Metall"}'::jsonb, '{"en": "Spot different aircraft: distinct registrations.", "de": "Entdecke verschiedene Flugzeuge: verschiedene Registrierungen."}'::jsonb, 'milestones', 'leveled', '{"metric": "registrations_distinct"}'::jsonb, '{5,10,25,50,100,250,500}', false, null, 3),
  ('old_friend', '{"en": "Old Friend", "de": "Alter Bekannter"}'::jsonb, '{"en": "Meet the same aircraft again on different days.", "de": "Triff dasselbe Flugzeug an verschiedenen Tagen wieder."}'::jsonb, 'milestones', 'leveled', '{"metric": "same_registration_days"}'::jsonb, '{2,3,5,10}', false, null, 4),
  ('busy_day', '{"en": "Busy Day", "de": "Voller Tag"}'::jsonb, '{"en": "Check in many aircraft on a single day.", "de": "Checke an einem einzigen Tag viele Flugzeuge ein."}'::jsonb, 'milestones', 'leveled', '{"metric": "checkins_in_one_day"}'::jsonb, '{5,10,25}', false, null, 5),
  ('daily_spotter', '{"en": "Daily Spotter", "de": "Täglicher Spotter"}'::jsonb, '{"en": "Check in on consecutive days.", "de": "Checke an aufeinanderfolgenden Tagen ein."}'::jsonb, 'milestones', 'leveled', '{"metric": "streak_days"}'::jsonb, '{3,7,14,30}', false, null, 6),
  ('weekend_warrior', '{"en": "Weekend Warrior", "de": "Wochenend-Spotter"}'::jsonb, '{"en": "Check in on consecutive weekends.", "de": "Checke an aufeinanderfolgenden Wochenenden ein."}'::jsonb, 'milestones', 'leveled', '{"metric": "streak_weekends"}'::jsonb, '{2,4,8,16}', false, null, 7),
  ('gate_hopper', '{"en": "Gate Hopper", "de": "Flughafen-Hopper"}'::jsonb, '{"en": "Visit different airports.", "de": "Besuche verschiedene Flughäfen."}'::jsonb, 'airports', 'leveled', '{"metric": "airports_distinct"}'::jsonb, '{3,5,10,25,50,100}', false, null, 8),
  ('home_base', '{"en": "Home Base", "de": "Heimatbasis"}'::jsonb, '{"en": "Check in many times at the same airport.", "de": "Checke oft am selben Flughafen ein."}'::jsonb, 'airports', 'leveled', '{"metric": "airport_repeat_max"}'::jsonb, '{10,25,50,100,250}', false, null, 9),
  ('home_turf', '{"en": "Home Turf", "de": "Heimspiel"}'::jsonb, '{"en": "Check in at your home airport.", "de": "Checke an deinem Heimatflughafen ein."}'::jsonb, 'airports', 'single', '{"metric": "home_airport_checkin"}'::jsonb, '{1}', false, null, 10),
  ('continental', '{"en": "Continental", "de": "Kontinental"}'::jsonb, '{"en": "Check in at airports on different continents.", "de": "Checke an Flughäfen auf verschiedenen Kontinenten ein."}'::jsonb, 'airports', 'leveled', '{"metric": "continents_distinct"}'::jsonb, '{2,3,4,5,6}', false, null, 11),
  ('island_hopper', '{"en": "Island Hopper", "de": "Inselhüpfer"}'::jsonb, '{"en": "Visit different island airports.", "de": "Besuche verschiedene Inselflughäfen."}'::jsonb, 'airports', 'leveled', '{"metric": "airports_where", "where": "island"}'::jsonb, '{1,3,5,10}', false, 'infinity', 12),
  ('short_field', '{"en": "Short Field", "de": "Kurze Piste"}'::jsonb, '{"en": "Visit an airport with a runway shorter than 1000 m.", "de": "Besuche einen Flughafen mit einer Piste unter 1000 m."}'::jsonb, 'airports', 'single', '{"metric": "airports_where", "where": "short_runway"}'::jsonb, '{1}', false, 'infinity', 13),
  ('high_altitude', '{"en": "High Altitude", "de": "Dicke Luft"}'::jsonb, '{"en": "Visit an airport higher than 2500 m.", "de": "Besuche einen Flughafen über 2500 m Höhe."}'::jsonb, 'airports', 'single', '{"metric": "airports_where", "where": "high_altitude"}'::jsonb, '{1}', false, null, 14),
  ('arctic_circle', '{"en": "Arctic Circle", "de": "Polarkreis"}'::jsonb, '{"en": "Visit an airport north of the Arctic Circle.", "de": "Besuche einen Flughafen nördlich des Polarkreises."}'::jsonb, 'airports', 'single', '{"metric": "airports_where", "where": "arctic"}'::jsonb, '{1}', false, null, 15),
  ('southern_cross', '{"en": "Southern Cross", "de": "Kreuz des Südens"}'::jsonb, '{"en": "Visit an airport in the southern hemisphere.", "de": "Besuche einen Flughafen auf der Südhalbkugel."}'::jsonb, 'airports', 'single', '{"metric": "airports_where", "where": "southern"}'::jsonb, '{1}', false, null, 16),
  ('passport_stamps', '{"en": "Passport Stamps", "de": "Reisestempel"}'::jsonb, '{"en": "Check in at airports in different countries.", "de": "Checke an Flughäfen in verschiedenen Ländern ein."}'::jsonb, 'countries', 'leveled', '{"metric": "airport_countries_distinct"}'::jsonb, '{2,3,5,10,15,25,50}', false, null, 17),
  ('register_collector', '{"en": "Register Collector", "de": "Register-Sammler"}'::jsonb, '{"en": "Spot aircraft from different countries of registration.", "de": "Entdecke Flugzeuge aus verschiedenen Zulassungsländern."}'::jsonb, 'countries', 'leveled', '{"metric": "register_countries_distinct"}'::jsonb, '{3,5,10,20,30,50}', false, null, 18),
  ('far_from_home', '{"en": "Far From Home", "de": "Weit weg von zu Hause"}'::jsonb, '{"en": "Spot aircraft outside their own register''s country.", "de": "Entdecke Flugzeuge außerhalb ihres Zulassungslandes."}'::jsonb, 'countries', 'leveled', '{"metric": "far_from_home"}'::jsonb, '{5,25,100}', false, null, 19),
  ('home_team', '{"en": "Home Team", "de": "Heimmannschaft"}'::jsonb, '{"en": "Spot different aircraft from your home airport''s country.", "de": "Entdecke verschiedene Flugzeuge aus dem Land deines Heimatflughafens."}'::jsonb, 'countries', 'leveled', '{"metric": "home_team"}'::jsonb, '{10,50,250}', false, null, 20),
  ('neighbourhood_watch', '{"en": "Neighbourhood Watch", "de": "Nachbarschaftswache"}'::jsonb, '{"en": "See different registration countries at one airport.", "de": "Sieh verschiedene Zulassungsländer an einem Flughafen."}'::jsonb, 'countries', 'leveled', '{"metric": "register_countries_at_airport_max"}'::jsonb, '{3,5,10}', false, null, 21),
  ('global_fleet', '{"en": "Global Fleet", "de": "Weltflotte"}'::jsonb, '{"en": "Spot aircraft registered on different continents.", "de": "Entdecke Flugzeuge, die auf verschiedenen Kontinenten zugelassen sind."}'::jsonb, 'countries', 'leveled', '{"metric": "register_continents_distinct"}'::jsonb, '{2,3,4,5,6}', false, null, 22),
  ('type_rater', '{"en": "Type Rater", "de": "Typ-Berechtigung"}'::jsonb, '{"en": "Spot different aircraft types.", "de": "Entdecke verschiedene Flugzeugtypen."}'::jsonb, 'types', 'leveled', '{"metric": "types_distinct"}'::jsonb, '{3,5,10,25,50,100}', false, null, 23),
  ('superjumbo', '{"en": "Superjumbo", "de": "Superjumbo"}'::jsonb, '{"en": "Spot an Airbus A380.", "de": "Entdecke einen Airbus A380."}'::jsonb, 'types', 'single', '{"metric": "types_in_family", "family": "A380"}'::jsonb, '{1}', false, null, 24),
  ('queen_of_the_skies', '{"en": "Queen of the Skies", "de": "Königin der Lüfte"}'::jsonb, '{"en": "Spot a Boeing 747, any variant.", "de": "Entdecke eine Boeing 747, egal welche Variante."}'::jsonb, 'types', 'single', '{"metric": "types_in_family", "family": "747"}'::jsonb, '{1}', false, null, 25),
  ('dreamliner', '{"en": "Dreamliner", "de": "Dreamliner"}'::jsonb, '{"en": "Spot a Boeing 787, any variant.", "de": "Entdecke eine Boeing 787, egal welche Variante."}'::jsonb, 'types', 'single', '{"metric": "types_in_family", "family": "787"}'::jsonb, '{1}', false, null, 26),
  ('triple_seven', '{"en": "Triple Seven", "de": "Triple Seven"}'::jsonb, '{"en": "Spot different Boeing 777 types.", "de": "Entdecke verschiedene Boeing-777-Typen."}'::jsonb, 'types', 'leveled', '{"metric": "types_in_family", "family": "777"}'::jsonb, '{2,4,6}', false, null, 27),
  ('airbus_fan', '{"en": "Airbus Fan", "de": "Airbus-Fan"}'::jsonb, '{"en": "Spot different Airbus types.", "de": "Entdecke verschiedene Airbus-Typen."}'::jsonb, 'types', 'leveled', '{"metric": "types_by_manufacturer", "manufacturer": "Airbus"}'::jsonb, '{3,6,10,20}', false, null, 28),
  ('boeing_fan', '{"en": "Boeing Fan", "de": "Boeing-Fan"}'::jsonb, '{"en": "Spot different Boeing types.", "de": "Entdecke verschiedene Boeing-Typen."}'::jsonb, 'types', 'leveled', '{"metric": "types_by_manufacturer", "manufacturer": "Boeing"}'::jsonb, '{3,6,10,20}', false, null, 29),
  ('prop_power', '{"en": "Prop Power", "de": "Propellerkraft"}'::jsonb, '{"en": "Spot different turboprop types.", "de": "Entdecke verschiedene Turboprop-Typen."}'::jsonb, 'types', 'leveled', '{"metric": "types_by_engine", "engine_type": "turboprop"}'::jsonb, '{1,3,5,10}', false, null, 30),
  ('early_bird', '{"en": "Early Bird", "de": "Frühaufsteher"}'::jsonb, '{"en": "Check in between 04:00 and 06:00 local time.", "de": "Checke zwischen 04:00 und 06:00 Ortszeit ein."}'::jsonb, 'time', 'leveled', '{"metric": "local_hour_between", "start": 4, "end": 6}'::jsonb, '{1,10,25}', false, null, 31),
  ('night_owl', '{"en": "Night Owl", "de": "Nachteule"}'::jsonb, '{"en": "Check in between 22:00 and 04:00 local time.", "de": "Checke zwischen 22:00 und 04:00 Ortszeit ein."}'::jsonb, 'time', 'leveled', '{"metric": "local_hour_between", "start": 22, "end": 4}'::jsonb, '{1,10,25}', false, null, 32),
  ('anniversary', '{"en": "Anniversary", "de": "Jahrestag"}'::jsonb, '{"en": "Check in on the day you joined, in the years after.", "de": "Checke an dem Tag ein, an dem du dabei bist, in den Jahren danach."}'::jsonb, 'time', 'leveled', '{"metric": "anniversary"}'::jsonb, '{1,2,3,5,10}', false, null, 33),
  ('deja_vu', '{"en": "Déjà Vu", "de": "Déjà-vu"}'::jsonb, '{"en": "The same registration at the same airport on 3 different days.", "de": "Dieselbe Registrierung am selben Flughafen an 3 verschiedenen Tagen."}'::jsonb, 'hidden', 'single', '{"metric": "same_registration_airport_days"}'::jsonb, '{3}', true, null, 34),
  ('mirror_image', '{"en": "Mirror Image", "de": "Spiegelbild"}'::jsonb, '{"en": "A registration that reads the same backwards.", "de": "Eine Registrierung, die rückwärts gleich gelesen wird."}'::jsonb, 'hidden', 'single', '{"metric": "palindrome_registrations"}'::jsonb, '{1}', true, null, 35),
  ('new_year', '{"en": "New Year''s Spot", "de": "Neujahrs-Spot"}'::jsonb, '{"en": "A check-in on 1 January.", "de": "Ein Check-in am 1. Januar."}'::jsonb, 'hidden', 'single', '{"metric": "checkins_on_date", "month": 1, "day": 1}'::jsonb, '{1}', true, null, 36);

create or replace function public.sync_checkins(items jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  item jsonb;
  results jsonb := '[]'::jsonb;
  v_id uuid;
  v_registration text;
  v_type text;
  v_airport integer;
  v_latitude double precision;
  v_longitude double precision;
  v_occurred timestamptz;
  v_visibility text;
  v_aircraft integer;
  v_inserted integer;
  v_owner uuid;
  engine jsonb := '{}'::jsonb;
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if jsonb_typeof(items) is distinct from 'array' then
    raise exception 'items must be an array' using errcode = '22023';
  end if;
  if jsonb_array_length(items) > 50 then
    raise exception 'at most 50 items per call' using errcode = '22023';
  end if;

  for item in select value from jsonb_array_elements(items) loop
    v_id := null;
    begin
      v_id := (item ->> 'id')::uuid;

      if item ->> 'kind' is distinct from 'spotted' then
        results := results || jsonb_build_object('id', v_id, 'status', 'rejected', 'code', 'unsupported_kind');
        continue;
      end if;

      v_registration := nullif(item ->> 'registration', '');
      v_type := nullif(item ->> 'type_icao', '');
      if v_registration is null and v_type is null then
        results := results || jsonb_build_object('id', v_id, 'status', 'rejected', 'code', 'missing_aircraft');
        continue;
      end if;
      if v_registration is not null and v_registration !~ '^[A-Z0-9]{1,6}(-[A-Z0-9]{1,6})?$' then
        results := results || jsonb_build_object('id', v_id, 'status', 'rejected', 'code', 'invalid_registration');
        continue;
      end if;

      v_occurred := (item ->> 'occurred_at')::timestamptz;
      if v_occurred is null or v_occurred > now() + interval '1 day' then
        results := results || jsonb_build_object('id', v_id, 'status', 'rejected', 'code', 'invalid_time');
        continue;
      end if;

      if v_type is not null
         and not exists (select 1 from public.aircraft_types t where t.icao_code = v_type) then
        results := results || jsonb_build_object('id', v_id, 'status', 'rejected', 'code', 'unknown_type');
        continue;
      end if;

      v_airport := (item ->> 'airport_id')::integer;
      if v_airport is not null
         and not exists (select 1 from public.airports a where a.id = v_airport) then
        results := results || jsonb_build_object('id', v_id, 'status', 'rejected', 'code', 'unknown_airport');
        continue;
      end if;

      v_latitude := (item ->> 'latitude')::double precision;
      v_longitude := (item ->> 'longitude')::double precision;
      if (v_latitude is null) <> (v_longitude is null)
         or v_latitude not between -90 and 90 or v_longitude not between -180 and 180 then
        results := results || jsonb_build_object('id', v_id, 'status', 'rejected', 'code', 'invalid_location');
        continue;
      end if;

      v_visibility := coalesce(item ->> 'visibility', 'private');
      if v_visibility not in ('public', 'friends', 'private') then
        results := results || jsonb_build_object('id', v_id, 'status', 'rejected', 'code', 'invalid_visibility');
        continue;
      end if;

      v_aircraft := null;
      if v_registration is not null then
        insert into public.aircraft (registration, data_status, country_code)
        values (v_registration, 'user_submitted', private.register_country(v_registration))
        on conflict (registration) do nothing;
        select a.id into v_aircraft from public.aircraft a where a.registration = v_registration;
      end if;

      insert into public.checkins (id, user_id, kind, occurred_at, aircraft_id, type_icao, airport_id,
                                   location, visibility)
      values (v_id, uid, 'spotted', v_occurred, v_aircraft, v_type, v_airport,
              case when v_latitude is null then null
                   else extensions.st_makepoint(v_longitude, v_latitude)::extensions.geography end,
              v_visibility)
      on conflict (id) do nothing;
      get diagnostics v_inserted = row_count;

      if v_inserted = 0 then
        -- Already stored. That is fine if it is this user's own earlier upload.
        select c.user_id into v_owner from public.checkins c where c.id = v_id;
        if v_owner is distinct from uid then
          results := results || jsonb_build_object('id', v_id, 'status', 'rejected', 'code', 'id_taken');
          continue;
        end if;
      end if;

      results := results || jsonb_build_object('id', v_id, 'status', 'stored');
    exception
      when data_exception or not_null_violation or check_violation then
        -- A malformed field. The item's partial writes are rolled back.
        results := results || jsonb_build_object('id', v_id, 'status', 'rejected', 'code', 'invalid_request');
    end;
  end loop;

  -- Badges and XP come after the check-ins are stored. If they fail, the upload still succeeds and
  -- the phone gets the same answer as before, so a broken rule can never block sync.
  begin
    engine := private.evaluate_badges(uid);
  exception when others then
    raise warning 'badge evaluation failed: %', sqlerrm;
    engine := '{}'::jsonb;
  end;

  return jsonb_build_object('results', results) || engine;
end;
$$;

revoke execute on function public.sync_checkins(jsonb) from public;
grant execute on function public.sync_checkins(jsonb) to authenticated;

