-- Spotting locations as places you check in at (docs/SPOTTING-LOCATIONS-PLAN.md, PR 1: backend).
-- A location belongs to an airport and waits for approval. A session is an airport visit at a location, and the
-- sightings made during it point at that visit with visit_id. Photos, badges and the apps come in later PRs.

alter table public.spotting_locations
  add column facing text check (char_length(facing) <= 200),
  add column tips text check (char_length(tips) <= 1000),
  add column photo_path text,
  add column created_at timestamptz not null default now();
alter table public.spotting_locations add constraint spotting_locations_name_length check (char_length(name) between 3 and 80);
alter table public.spotting_locations add constraint spotting_locations_description_length check (char_length(description) <= 1000);

-- A sighting made during a session. No foreign key: deleting the visit only clears the link (trigger below).
alter table public.checkins add column visit_id uuid;
create index checkins_visit_idx on public.checkins (visit_id) where visit_id is not null;

-- Nobody can sit on a pile of unreviewed places: ten waiting at a time.
create function private.limit_pending_locations() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.created_by is not null and new.status = 'pending'
     and (select count(*) from public.spotting_locations s where s.created_by = new.created_by and s.status = 'pending') >= 10 then
    raise exception 'too many spotting locations are waiting for approval' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
revoke execute on function private.limit_pending_locations() from public, anon, authenticated;
create trigger spotting_locations_limit before insert on public.spotting_locations
  for each row execute function private.limit_pending_locations();

-- Deleting a visit unlinks its sightings. They stay in the logbook.
create function private.unlink_visit_sightings() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  update public.checkins c set visit_id = null where c.visit_id = old.id;
  return null;
end;
$$;
revoke execute on function private.unlink_visit_sightings() from public, anon, authenticated;
create trigger checkins_unlink_sightings after delete on public.checkins
  for each row when (old.kind = 'airport') execute function private.unlink_visit_sightings();

-- The location a visit names counts only if the caller may see it and it is at the visit's airport.
create function private.valid_spot_location(uid uuid, spot integer, airport integer) returns integer
language sql stable security definer set search_path = '' as $$
  select s.id from public.spotting_locations s
  where s.id = spot and s.airport_id = airport and (s.status = 'approved' or s.created_by = uid);
$$;
revoke execute on function private.valid_spot_location(uuid, integer, integer) from public, anon, authenticated;

-- The visit a sighting belongs to must be the caller's own visit, and the sighting not older than the visit by a day.
create function private.valid_visit(uid uuid, visit uuid, own uuid) returns uuid
language sql stable security definer set search_path = '' as $$
  select v.id from public.checkins v
  where v.id = visit and v.id <> own and v.user_id = uid and v.kind = 'airport';
$$;
revoke execute on function private.valid_visit(uuid, uuid, uuid) from public, anon, authenticated;

-- The upload takes spot_location_id (for visits) and visit_id (for sightings). Both are dropped when they don't hold,
-- so a bad link never blocks the check-in itself. Patched in place, like the earlier columns.
do $$
declare
  def text := pg_get_functiondef('public.sync_checkins(jsonb)'::regprocedure);
  columns_marker text := 'visit_context, flight_id, source_checkin_id, origin_id';
  values_marker text := E'private.valid_tag_source(uid, nullif(item ->> ''source_checkin_id'', '''')::uuid, v_id),';
begin
  if position(columns_marker in def) = 0 or position(values_marker in def) = 0 then
    raise exception 'sync_checkins has no insert to anchor on';
  end if;
  execute replace(replace(def, columns_marker, 'visit_context, flight_id, source_checkin_id, spot_location_id, visit_id, origin_id'),
    values_marker, values_marker
      || E' case when v_kind = ''airport'' then private.valid_spot_location(uid, nullif(item ->> ''spot_location_id'', '''')::integer, v_airport) end,'
      || E' case when v_kind = ''spotted'' then private.valid_visit(uid, nullif(item ->> ''visit_id'', '''')::uuid, v_id) end,');
end;
$$;

-- Suggest a new place. The airport is the nearest one to the pin, within 150 km. A place of about the same name within
-- 100 m is reported back instead of added twice.
create function public.add_spotting_location(
  p_name text, p_latitude double precision, p_longitude double precision,
  p_description text default null, p_best_time text default null, p_facing text default null,
  p_tips text default null, p_legal_notes text default null
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  v_name text := btrim(coalesce(p_name, ''));
  v_point extensions.geography;
  v_airport integer;
  v_duplicate integer;
  v_id integer;
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if char_length(v_name) < 3 or char_length(v_name) > 80 then
    return jsonb_build_object('status', 'rejected', 'code', 'invalid_name');
  end if;
  if p_latitude is null or p_longitude is null or p_latitude not between -90 and 90 or p_longitude not between -180 and 180 then
    return jsonb_build_object('status', 'rejected', 'code', 'invalid_location');
  end if;
  v_point := extensions.st_setsrid(extensions.st_makepoint(p_longitude, p_latitude), 4326)::extensions.geography;

  select a.id into v_airport from public.airports a
  where extensions.st_dwithin(a.location, v_point, 150000)
  order by a.location operator(extensions.<->) v_point limit 1;
  if v_airport is null then
    return jsonb_build_object('status', 'rejected', 'code', 'no_airport_nearby');
  end if;

  select s.id into v_duplicate from public.spotting_locations s
  where s.airport_id = v_airport and (s.status = 'approved' or s.created_by = uid)
    and s.location is not null and extensions.st_dwithin(s.location, v_point, 100)
    and lower(s.name) = lower(v_name)
  limit 1;
  if v_duplicate is not null then
    return jsonb_build_object('status', 'duplicate', 'id', v_duplicate);
  end if;

  insert into public.spotting_locations (airport_id, name, location, description, best_time, facing, tips, legal_notes, created_by)
  values (v_airport, v_name, v_point, nullif(btrim(p_description), ''), nullif(btrim(p_best_time), ''),
          nullif(btrim(p_facing), ''), nullif(btrim(p_tips), ''), nullif(btrim(p_legal_notes), ''), uid)
  returning id into v_id;
  return jsonb_build_object('status', 'pending', 'id', v_id, 'airport_id', v_airport);
exception
  when data_exception or check_violation then
    return jsonb_build_object('status', 'rejected', 'code', 'invalid_request');
  when sqlstate 'P0001' then
    return jsonb_build_object('status', 'rejected', 'code', 'too_many_pending');
end;
$$;

-- The places at an airport: approved ones, and the caller's own waiting ones. Nearest to the airport first.
create function public.spotting_locations_at(p_airport integer)
returns table (id integer, name text, latitude double precision, longitude double precision, description text,
               best_time text, facing text, tips text, legal_notes text, photo_path text, status text, mine boolean,
               sessions integer)
language sql stable security definer set search_path = '' as $$
  select s.id, s.name, extensions.st_y(s.location::extensions.geometry), extensions.st_x(s.location::extensions.geometry),
         s.description, s.best_time, s.facing, s.tips, s.legal_notes, s.photo_path, s.status,
         s.created_by is not distinct from auth.uid(),
         (select count(*)::integer from public.checkins v
          where v.spot_location_id = s.id and v.kind = 'airport' and (v.visibility = 'public' or v.user_id = auth.uid()))
  from public.spotting_locations s
  where auth.uid() is not null and s.airport_id = p_airport
    and (s.status = 'approved' or s.created_by = auth.uid())
  order by s.name;
$$;

-- One place with its numbers: public sessions and the aircraft seen in them, plus the caller's own.
create function public.get_spotting_location(p_id integer) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', s.id, 'airport_id', s.airport_id, 'airport', a.name, 'iata', a.iata, 'name', s.name,
    'latitude', extensions.st_y(s.location::extensions.geometry), 'longitude', extensions.st_x(s.location::extensions.geometry),
    'description', s.description, 'best_time', s.best_time, 'facing', s.facing, 'tips', s.tips,
    'legal_notes', s.legal_notes, 'photo_path', s.photo_path, 'status', s.status,
    'mine', s.created_by is not distinct from auth.uid(),
    'sessions', (select count(*) from public.checkins v
                 where v.spot_location_id = s.id and v.kind = 'airport' and v.visibility = 'public'),
    'aircraft', (select count(*) from public.checkins x
                 join public.checkins v on v.id = x.visit_id
                 where v.spot_location_id = s.id and v.kind = 'airport' and v.visibility = 'public' and x.visibility = 'public'),
    'my_sessions', (select count(*) from public.checkins v
                    where v.spot_location_id = s.id and v.kind = 'airport' and v.user_id = auth.uid())
  )
  from public.spotting_locations s join public.airports a on a.id = s.airport_id
  where auth.uid() is not null and s.id = p_id and (s.status = 'approved' or s.created_by = auth.uid());
$$;

-- The aircraft seen during a session, as far as the caller may see each sighting.
create function public.get_visit_sightings(p_visit uuid)
returns table (id uuid, occurred_at timestamptz, registration text, type_icao text, user_id uuid)
language sql stable security definer set search_path = '' as $$
  select x.id, x.occurred_at, a.registration, x.type_icao, x.user_id
  from public.checkins x
  join public.checkins v on v.id = x.visit_id and v.user_id = x.user_id
  left join public.aircraft a on a.id = x.aircraft_id
  where auth.uid() is not null and x.visit_id = p_visit and v.kind = 'airport'
    and private.can_view_checkin(v.id) and private.can_view_checkin(x.id)
  order by x.occurred_at, x.id;
$$;

revoke execute on function public.add_spotting_location(text, double precision, double precision, text, text, text, text, text) from public, anon;
revoke execute on function public.spotting_locations_at(integer) from public, anon;
revoke execute on function public.get_spotting_location(integer) from public, anon;
revoke execute on function public.get_visit_sightings(uuid) from public, anon;
grant execute on function public.add_spotting_location(text, double precision, double precision, text, text, text, text, text) to authenticated;
grant execute on function public.spotting_locations_at(integer) to authenticated;
grant execute on function public.get_spotting_location(integer) to authenticated;
grant execute on function public.get_visit_sightings(uuid) to authenticated;
