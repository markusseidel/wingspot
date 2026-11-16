-- The Boeing 757 (B752, B753). Hosted has only a short list of aircraft types until the licensing question for the
-- full list is answered, and a check-in with any other type is rejected as unknown_type.
insert into public.aircraft_types (icao_code, manufacturer, model, family, engine_type, engine_count, wtc) values
  ('B752', 'Boeing', '757-200', '757', 'jet', 2, 'M'),
  ('B753', 'Boeing', '757-300', '757', 'jet', 2, 'M')
on conflict (icao_code) do nothing;
