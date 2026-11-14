-- Three hidden badges for the total distance of your flights: more than the radius of the Earth (6,371 km), more
-- than its circumference (40,075 km) and more than the distance to the Moon (384,400 km). The distance of each
-- flight is the one the server worked out when it was saved (distance_km).

-- The new metric is added to the badge evaluation in place, so the long function isn't copied again.
do $$
declare
  def text := pg_get_functiondef('private.badge_values(uuid)'::regprocedure);
  marker text := 'when ''checkins_total'' then';
begin
  if position(marker in def) = 0 then
    raise exception 'badge_values has no checkins_total metric to anchor on';
  end if;
  execute replace(def, marker,
    'when ''distance_flown_km'' then (select coalesce(sum(c.distance_km), 0) from public.checkins c '
    || 'where c.user_id = uid and c.kind = ''flown'') ' || marker);
end;
$$;

insert into public.badges (id, name, description, category, kind, rule, levels, hidden, valid_from, position) values
  ('earth_radius', '{"en": "Down to the Core", "de": "Bis zum Erdkern"}'::jsonb,
   '{"en": "Fly more than the radius of the Earth: over 6,371 km in total.", "de": "Fliege mehr als den Erdradius: insgesamt über 6.371 km."}'::jsonb,
   'hidden', 'single', '{"metric": "distance_flown_km"}'::jsonb, '{6372}', true, null, 37),
  ('earth_circumference', '{"en": "Around the World", "de": "Einmal um die Welt"}'::jsonb,
   '{"en": "Fly more than the circumference of the Earth: over 40,075 km in total.", "de": "Fliege mehr als den Erdumfang: insgesamt über 40.075 km."}'::jsonb,
   'hidden', 'single', '{"metric": "distance_flown_km"}'::jsonb, '{40076}', true, null, 38),
  ('to_the_moon', '{"en": "To the Moon", "de": "Zum Mond"}'::jsonb,
   '{"en": "Fly more than the distance to the Moon: over 384,400 km in total.", "de": "Fliege mehr als die Entfernung zum Mond: insgesamt über 384.400 km."}'::jsonb,
   'hidden', 'single', '{"metric": "distance_flown_km"}'::jsonb, '{384401}', true, null, 39);
