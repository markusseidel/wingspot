-- One feed entry per flight, and the flight carries its badges (issues #255 and #256).
--
-- A flight check-in stores three rows: the flight and a departing and an arriving airport visit. The visits are
-- linked to their flight by flight_id (20261120200000). Two things went wrong because the three rows share a moment:
--  * the feed showed all three on Android (iOS hid the visits on the phone, by matching time and airport code);
--  * a badge is tied to the person's newest check-in, and with equal created_at the id decided, so it landed on one of
--    the three rows by chance, usually a visit that the feed does not show.
-- Now the server decides both. The visits stay stored (stats, airport pages, badges), they just aren't feed entries.

-- True for an airport visit that belongs to a flight the person also checked in. A visit with a flight_id belongs to
-- that flight if it exists; one without (made before the link, or by an app that doesn't send it) belongs to a flight
-- of the same person at the same time that starts or ends at that airport, as the 20261120200000 backfill matched.
-- It takes the check-in's id and reads the row itself, because callers like get_feed run as the signed-in person, who
-- has no direct access to every column.
create function private.is_flight_visit(p_checkin uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.checkins v
    join public.checkins f on f.user_id = v.user_id and f.kind = 'flown'
      and (f.id = v.flight_id
           or (v.flight_id is null and f.occurred_at = v.occurred_at and v.airport_id in (f.origin_id, f.destination_id)))
    where v.id = p_checkin and v.kind = 'airport');
$$;
revoke execute on function private.is_flight_visit(uuid) from public, anon, authenticated;
grant execute on function private.is_flight_visit(uuid) to authenticated;

-- get_feed leaves the flights' visits out. Everything else is as in 20261115100000. Standalone airport check-ins stay.
create or replace function public.get_feed(before_time timestamptz default null, before_id uuid default null,
                                           page_size integer default 30, sort_by text default 'occurred')
returns table (
  id uuid, user_id uuid, username text, display_name text, kind public.checkin_kind,
  occurred_at timestamptz, registration text, type_icao text, type_name text,
  airport_id integer, airport_code text, origin_code text, destination_code text,
  flight_number text, distance_km integer, salutes integer, comments integer, saluted boolean,
  cursor_time timestamptz
)
language sql stable security invoker set search_path = '' as $$
  select
    c.id, c.user_id, p.username, p.display_name, c.kind, c.occurred_at,
    case when a.is_sensitive and c.user_id <> auth.uid() then null else a.registration end,
    coalesce(c.type_icao, a.type_icao),
    t.manufacturer || ' ' || t.model,
    c.airport_id, coalesce(ap.iata, ap.icao),
    coalesce(o.iata, o.icao), coalesce(d.iata, d.icao),
    c.flight_number, c.distance_km,
    (select count(*)::integer from public.salutes s where s.checkin_id = c.id),
    (select count(*)::integer from public.comments m where m.checkin_id = c.id),
    exists (select 1 from public.salutes s where s.checkin_id = c.id and s.user_id = auth.uid()),
    case when sort_by = 'created' then c.created_at else c.occurred_at end
  from public.checkins c
  join public.profiles p on p.id = c.user_id
  left join public.aircraft a on a.id = c.aircraft_id
  left join public.aircraft_types t on t.icao_code = coalesce(c.type_icao, a.type_icao)
  left join public.airports ap on ap.id = c.airport_id
  left join public.airports o on o.id = c.origin_id
  left join public.airports d on d.id = c.destination_id
  where (c.user_id = auth.uid()
         or exists (select 1 from public.follows f where f.follower = auth.uid() and f.followee = c.user_id))
    and not private.is_flight_visit(c.id)
    and (before_time is null
         or (case when sort_by = 'created' then c.created_at else c.occurred_at end, c.id) < (before_time, before_id))
  order by case when sort_by = 'created' then c.created_at else c.occurred_at end desc, c.id desc
  limit least(greatest(coalesce(page_size, 30), 1), 50);
$$;

-- A badge is tied to the newest check-in that is not a flight's visit, so a flight check-in carries its badges.
-- Patched in place, as 20261121000000 did.
do $$
declare
  def text := pg_get_functiondef('private.evaluate_badges(uuid, boolean)'::regprocedure);
  old_line text := 'from public.checkins c where c.user_id = uid order by c.created_at desc, c.id desc limit 1;';
  new_line text := 'from public.checkins c where c.user_id = uid'
    || E'\n    and not private.is_flight_visit(c.id)'
    || E'\n    order by c.created_at desc, c.id desc limit 1;';
begin
  if position(old_line in def) = 0 then
    raise exception 'evaluate_badges has no place to anchor on';
  end if;
  execute replace(def, old_line, new_line);
end;
$$;

-- Badges that already sit on a flight's visit move to the flight. Only the link changes.
update public.user_badges ub
set checkin_id = m.flight_id
from (
  select distinct on (v.id) v.id as visit_id, f.id as flight_id
  from public.checkins v
  join public.checkins f on f.user_id = v.user_id and f.kind = 'flown'
    and (f.id = v.flight_id or (v.flight_id is null and f.occurred_at = v.occurred_at and v.airport_id in (f.origin_id, f.destination_id)))
  where v.kind = 'airport'
  order by v.id, f.id
) m
where ub.checkin_id = m.visit_id;
