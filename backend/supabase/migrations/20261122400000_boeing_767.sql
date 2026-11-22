-- The Boeing 767 (B762, B763, B764), requested by a tester. Hosted has only a short list of aircraft types until the
-- licensing question for the full list is answered, and a check-in with any other type is rejected as unknown_type.
insert into public.aircraft_types (icao_code, manufacturer, model, family, engine_type, engine_count, wtc) values
  ('B762', 'Boeing', '767-200', '767', 'jet', 2, 'H'),
  ('B763', 'Boeing', '767-300', '767', 'jet', 2, 'H'),
  ('B764', 'Boeing', '767-400ER', '767', 'jet', 2, 'H')
on conflict (icao_code) do nothing;
