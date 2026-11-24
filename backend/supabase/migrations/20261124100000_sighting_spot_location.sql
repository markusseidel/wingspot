-- A sighting can name its own spotting location (issue #286): the place picker on the sighting form, and on older sightings in the edit
-- screen, without a spotting session. A session still works as before; the sighting's own place wins over the session's.

-- 1. sync_checkins keeps spot_location_id for sightings too (validated like for a visit: approved, or your own waiting one, and at the
--    airport of the check-in; otherwise it is dropped and the check-in is stored anyway). On a repeated upload (edit) a sighting takes the
--    place the app sends; an app that does not send the field at all (older apps) leaves the place as it was. Sending null clears it.
do $$
declare
  def text := pg_get_functiondef('public.sync_checkins(jsonb)'::regprocedure);
  old_values text := E'case when v_kind = ''airport'' then private.valid_spot_location(uid, nullif(item ->> ''spot_location_id'', '''')::integer, v_airport) end';
  new_values text := E'case when v_kind in (''airport'', ''spotted'') then private.valid_spot_location(uid, nullif(item ->> ''spot_location_id'', '''')::integer, v_airport) end';
  old_update text := E'visit_context = excluded.visit_context\n        where checkins.user_id = uid;';
  new_update text := E'visit_context = excluded.visit_context,\n            spot_location_id = case when checkins.kind = ''spotted'' and item ? ''spot_location_id'' then excluded.spot_location_id else checkins.spot_location_id end\n        where checkins.user_id = uid;';
begin
  if position(old_values in def) = 0 or position(old_update in def) = 0 then
    raise exception 'sync_checkins has no place to anchor on';
  end if;
  execute replace(replace(def, old_values, new_values), old_update, new_update);
end;
$$;

-- 2. "Spotted at <place>": the sighting's own place when it has one, otherwise the one of its visit.
create or replace function public.get_checkin_spot(p_id uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'visit_id', case when c.kind = 'airport' then c.id else v.id end,
    'spot_id', s.id,
    'spot_name', s.name,
    'sightings', case when c.kind = 'airport'
      then (select count(*) from public.checkins x where x.visit_id = c.id and private.can_view_checkin(x.id))
    end)
  from public.checkins c
  left join public.checkins v on c.kind = 'spotted' and v.id = c.visit_id and v.user_id = c.user_id and v.kind = 'airport'
  left join public.spotting_locations s
    on s.id = case when c.kind = 'airport' then c.spot_location_id else coalesce(c.spot_location_id, v.spot_location_id) end
   and (s.status = 'approved' or (s.created_by = auth.uid() and s.status = 'pending'))
  where auth.uid() is not null and c.id = p_id and private.can_view_checkin(c.id)
    and (c.kind = 'airport' or (c.kind = 'spotted' and (v.id is not null or c.spot_location_id is not null)));
$$;

-- 3. The place page counts the public sightings of a place: those tagged directly, and those of a public session there that have no
--    place of their own (a sighting is counted once).
create or replace function public.get_spotting_location(p_id integer) returns jsonb
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
                 left join public.checkins v on v.id = x.visit_id and v.kind = 'airport' and v.visibility = 'public'
                 where x.kind = 'spotted' and x.visibility = 'public'
                   and coalesce(x.spot_location_id, v.spot_location_id) = s.id),
    'my_sessions', (select count(*) from public.checkins v
                    where v.spot_location_id = s.id and v.kind = 'airport' and v.user_id = auth.uid())
  )
  from public.spotting_locations s join public.airports a on a.id = s.airport_id
  where auth.uid() is not null and s.id = p_id and (s.status = 'approved' or (s.created_by = auth.uid() and s.status = 'pending'));
$$;

-- 4. The aircraft spotted at a place, newest first, for the people who may see each sighting: public ones, and your own. It covers both
--    ways of naming a place (the sighting's own, and its session's). Page with the last row's time and id.
create function public.get_spot_sightings(p_place integer, p_limit integer default 20, p_before_time timestamptz default null, p_before_id uuid default null)
returns table (id uuid, occurred_at timestamptz, registration text, type_icao text, type_name text, user_id uuid, username text, display_name text)
language sql stable security definer set search_path = '' as $$
  select x.id, x.occurred_at, ac.registration, x.type_icao, t.manufacturer || ' ' || t.model, x.user_id, p.username, p.display_name
  from public.checkins x
  join public.spotting_locations s on s.id = p_place and (s.status = 'approved' or (s.created_by = auth.uid() and s.status = 'pending'))
  left join public.checkins v on v.id = x.visit_id and v.user_id = x.user_id and v.kind = 'airport'
  left join public.aircraft ac on ac.id = x.aircraft_id
  left join public.aircraft_types t on t.icao_code = x.type_icao
  join public.profiles p on p.id = x.user_id
  where auth.uid() is not null and x.kind = 'spotted'
    and coalesce(x.spot_location_id, v.spot_location_id) = p_place
    and (x.visibility = 'public' or x.user_id = auth.uid())
    and (v.id is null or v.visibility = 'public' or x.user_id = auth.uid() or x.spot_location_id is not null)
    and private.can_view_checkin(x.id)
    and (p_before_time is null or (x.occurred_at, x.id) < (p_before_time, p_before_id))
  order by x.occurred_at desc, x.id desc
  limit least(greatest(coalesce(p_limit, 20), 1), 50);
$$;
revoke execute on function public.get_spot_sightings(integer, integer, timestamptz, uuid) from public, anon;
grant execute on function public.get_spot_sightings(integer, integer, timestamptz, uuid) to authenticated;
