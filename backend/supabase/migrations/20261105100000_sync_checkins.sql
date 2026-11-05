-- Check-in upload from the apps' offline outbox (docs/PHASE1.md, milestone 3).
--
-- Apps can't insert into checkins or aircraft directly. They call this function, which
-- stores each item on its own, so one bad item never blocks the rest of a batch, and which
-- is safe to repeat: an item whose id is already stored for the same user counts as stored.
--
-- Rules:
-- - Only spotted check-ins for now. Flown and airport check-ins come with milestone 5.
-- - The shared aircraft row holds only the registration. The type the user entered stays
--   on the check-in (PHASE1.md, decision 1).
-- - A check-in is private unless the app says otherwise. Privacy settings come later.
-- - Verification stays 'none'. XP and badges come with milestone 4.

create function public.sync_checkins(items jsonb) returns jsonb
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
        insert into public.aircraft (registration, data_status)
        values (v_registration, 'user_submitted')
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

  return jsonb_build_object('results', results);
end;
$$;

revoke execute on function public.sync_checkins(jsonb) from public;
grant execute on function public.sync_checkins(jsonb) to authenticated;
