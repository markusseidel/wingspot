-- The Airbus A340 (A342, A343, A345, A346), requested by the owner (#371). Hosted has only a short list of aircraft types until the
-- licensing question for the full list is answered, and a check-in with any other type is rejected as unknown_type.
insert into public.aircraft_types (icao_code, manufacturer, model, family, engine_type, engine_count, wtc) values
  ('A342', 'Airbus', 'A340-200', 'A340', 'jet', 4, 'H'),
  ('A343', 'Airbus', 'A340-300', 'A340', 'jet', 4, 'H'),
  ('A345', 'Airbus', 'A340-500', 'A340', 'jet', 4, 'H'),
  ('A346', 'Airbus', 'A340-600', 'A340', 'jet', 4, 'H')
on conflict (icao_code) do nothing;
