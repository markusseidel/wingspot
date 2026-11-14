-- The day of a flight can be corrected: when the owner's app sends a flight again with another time, the flight takes
-- it, and so do the two airport visits the flight created (same time, departing and arriving, at its two airports).
-- Spotted check-ins and airport visits keep their time, whatever the app sends. Editing is silent: no alert goes out.

-- The upsert in sync_checkins gets the time for flights, patched in place so the long function isn't copied again.
do $$
declare
  def text := pg_get_functiondef('public.sync_checkins(jsonb)'::regprocedure);
  marker text := 'set aircraft_id = excluded.aircraft_id, type_icao = excluded.type_icao,';
begin
  if position(marker in def) = 0 then
    raise exception 'sync_checkins has no update clause to anchor on';
  end if;
  execute replace(def, marker,
    'set occurred_at = case when checkins.kind = ''flown'' then excluded.occurred_at else checkins.occurred_at end, '
    || substr(marker, 5));
end;
$$;

create function private.move_flight_visits() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.checkins v set occurred_at = new.occurred_at
  where v.user_id = new.user_id and v.kind = 'airport' and v.visit_context in ('departing', 'arriving')
    and v.occurred_at = old.occurred_at and v.airport_id in (new.origin_id, new.destination_id);
  return null;
end;
$$;
revoke execute on function private.move_flight_visits() from public, anon, authenticated;

create trigger checkins_move_visits after update of occurred_at on public.checkins
  for each row when (new.kind = 'flown' and new.occurred_at is distinct from old.occurred_at)
  execute function private.move_flight_visits();
