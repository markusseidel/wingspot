-- Badges for spotting locations and sessions (docs/SPOTTING-LOCATIONS-PLAN.md, PR 4). A badge is data, so the apps need
-- no update for them to appear; the new category "spotting" shows with a default symbol until the apps name it.
-- Metrics, all over the caller's own check-ins:
--   spot_sessions_total          visits at a spotting location
--   spot_sessions_one_place_max  most visits at one location
--   spot_places_distinct         different locations visited
--   session_aircraft_max         most sightings linked to one visit
--   spot_places_added            own locations that were approved
--   spot_sessions_golden_hours   visits at a location that began at 05:00-08:59 or 17:00-20:59 local time
-- "Local time" is estimated from the airport's longitude, like the time badges.
do $$
declare
  def text := pg_get_functiondef('private.badge_values(uuid)'::regprocedure);
  marker text := 'when ''checkins_total'' then';
begin
  if position(marker in def) = 0 then
    raise exception 'badge_values has no checkins_total metric to anchor on';
  end if;
  execute replace(def, marker,
    'when ''spot_sessions_total'' then (select count(*) from public.checkins c where c.user_id = uid and c.kind = ''airport'' and c.spot_location_id is not null) '
    || 'when ''spot_sessions_one_place_max'' then (select max(n) from (select count(*) as n from public.checkins c where c.user_id = uid and c.kind = ''airport'' and c.spot_location_id is not null group by c.spot_location_id) s) '
    || 'when ''spot_places_distinct'' then (select count(distinct c.spot_location_id) from public.checkins c where c.user_id = uid and c.kind = ''airport'' and c.spot_location_id is not null) '
    || 'when ''session_aircraft_max'' then (select max(n) from (select count(*) as n from public.checkins x join public.checkins v on v.id = x.visit_id and v.user_id = x.user_id and v.kind = ''airport'' where x.user_id = uid and x.kind = ''spotted'' group by x.visit_id) s) '
    || 'when ''spot_places_added'' then (select count(*) from public.spotting_locations s where s.created_by = uid and s.status = ''approved'') '
    || 'when ''spot_sessions_golden_hours'' then (select count(*) from (select extract(hour from (c.occurred_at at time zone ''UTC'') + make_interval(hours => round(coalesce(extensions.st_x(ap.location::extensions.geometry), 0) / 15)::integer)) as h '
    || 'from public.checkins c left join public.airports ap on ap.id = c.airport_id where c.user_id = uid and c.kind = ''airport'' and c.spot_location_id is not null) t where t.h between 5 and 8 or t.h between 17 and 20) '
    || marker);
end;
$$;

insert into public.badges (id, name, description, category, kind, rule, levels, hidden, valid_from, position) values
  ('first_spot_session', '{"en": "First Session", "de": "Erste Session"}'::jsonb,
   '{"en": "Check in at a spotting location.", "de": "Checke an einem Spotting-Ort ein."}'::jsonb,
   'spotting', 'single', '{"metric": "spot_sessions_total"}'::jsonb, '{1}', false, null, 41),
  ('deck_regular', '{"en": "Deck Regular", "de": "Stammgast"}'::jsonb,
   '{"en": "Spend sessions at the same spotting location.", "de": "Verbringe mehrere Sessions am selben Spotting-Ort."}'::jsonb,
   'spotting', 'leveled', '{"metric": "spot_sessions_one_place_max"}'::jsonb, '{3,5,10,25}', false, null, 42),
  ('place_collector', '{"en": "Place Collector", "de": "Ortesammler"}'::jsonb,
   '{"en": "Visit different spotting locations.", "de": "Besuche verschiedene Spotting-Orte."}'::jsonb,
   'spotting', 'leveled', '{"metric": "spot_places_distinct"}'::jsonb, '{3,5,10}', false, null, 43),
  ('session_pro', '{"en": "Session Pro", "de": "Session-Profi"}'::jsonb,
   '{"en": "Spot many aircraft in a single session.", "de": "Sieh in einer einzigen Session viele Flugzeuge."}'::jsonb,
   'spotting', 'leveled', '{"metric": "session_aircraft_max"}'::jsonb, '{10,25,50}', false, null, 44),
  ('cartographer', '{"en": "Cartographer", "de": "Kartograf"}'::jsonb,
   '{"en": "Add a spotting location that gets approved.", "de": "Füge einen Spotting-Ort hinzu, der freigegeben wird."}'::jsonb,
   'spotting', 'leveled', '{"metric": "spot_places_added"}'::jsonb, '{1,3,10}', false, null, 45),
  ('sunrise_hunter', '{"en": "Sunrise Hunter", "de": "Sonnenjäger"}'::jsonb,
   '{"en": "Start a session in the early morning or the evening.", "de": "Starte eine Session am frühen Morgen oder am Abend."}'::jsonb,
   'spotting', 'leveled', '{"metric": "spot_sessions_golden_hours"}'::jsonb, '{1,5,15}', false, null, 46);
