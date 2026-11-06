-- Flown check-ins (milestone 5). A flight stores its route, flight number, cabin and seat. The distance
-- is worked out on the server from the two airports. Every check-in counts for badges and XP, so a
-- flight counts like any other check-in, and its aircraft counts if the user gave one.

create or replace function private.checkin_facts(uid uuid) returns table (
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
  where c.user_id = uid and c.kind in ('spotted', 'airport', 'flown');
$$;

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
  v_kind text;
  v_context text;
  v_origin integer;
  v_destination integer;
  v_flight text;
  v_cabin text;
  v_seat text;
  v_distance integer;
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

      v_kind := item ->> 'kind';
      if v_kind is null or v_kind not in ('spotted', 'airport', 'flown') then
        results := results || jsonb_build_object('id', v_id, 'status', 'rejected', 'code', 'unsupported_kind');
        continue;
      end if;

      v_registration := nullif(item ->> 'registration', '');
      v_type := nullif(item ->> 'type_icao', '');
      if v_kind = 'airport' then
        -- A visit is about the airport only. Any aircraft fields are ignored.
        v_registration := null;
        v_type := null;
      end if;
      if v_kind = 'spotted' and v_registration is null and v_type is null then
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

      if v_kind = 'airport' and v_airport is null then
        results := results || jsonb_build_object('id', v_id, 'status', 'rejected', 'code', 'missing_airport');
        continue;
      end if;

      v_context := case when v_kind = 'airport' then nullif(item ->> 'context', '') end;
      if v_context is not null
         and v_context not in ('spotting', 'departing', 'arriving', 'transit', 'working', 'museum') then
        results := results || jsonb_build_object('id', v_id, 'status', 'rejected', 'code', 'invalid_context');
        continue;
      end if;

      v_origin := null; v_destination := null; v_flight := null; v_cabin := null; v_seat := null; v_distance := null;
      if v_kind = 'flown' then
        v_origin := (item ->> 'origin_id')::integer;
        v_destination := (item ->> 'destination_id')::integer;
        if v_origin is null or v_destination is null then
          results := results || jsonb_build_object('id', v_id, 'status', 'rejected', 'code', 'missing_route');
          continue;
        end if;
        if v_origin = v_destination then
          results := results || jsonb_build_object('id', v_id, 'status', 'rejected', 'code', 'invalid_route');
          continue;
        end if;
        select round(extensions.st_distance(o.location, d.location) / 1000)::integer into v_distance
        from public.airports o, public.airports d where o.id = v_origin and d.id = v_destination;
        if not found then
          results := results || jsonb_build_object('id', v_id, 'status', 'rejected', 'code', 'unknown_airport');
          continue;
        end if;
        v_flight := upper(nullif(replace(item ->> 'flight_number', ' ', ''), ''));
        if v_flight is not null and v_flight !~ '^[A-Z0-9]{2}[0-9]{1,4}[A-Z]?$' then
          results := results || jsonb_build_object('id', v_id, 'status', 'rejected', 'code', 'invalid_flight_number');
          continue;
        end if;
        v_cabin := nullif(item ->> 'cabin', '');
        if v_cabin is not null and v_cabin not in ('economy', 'premium_economy', 'business', 'first') then
          results := results || jsonb_build_object('id', v_id, 'status', 'rejected', 'code', 'invalid_cabin');
          continue;
        end if;
        v_seat := upper(nullif(item ->> 'seat', ''));
        if v_seat is not null and v_seat !~ '^[0-9]{1,3}[A-Z]$' then
          results := results || jsonb_build_object('id', v_id, 'status', 'rejected', 'code', 'invalid_seat');
          continue;
        end if;
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
                                   visit_context, origin_id, destination_id, flight_number, cabin_class, seat,
                                   distance_km, location, visibility)
      values (v_id, uid, v_kind::public.checkin_kind, v_occurred, v_aircraft, v_type, v_airport, v_context,
              v_origin, v_destination, v_flight, v_cabin, v_seat, v_distance,
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
