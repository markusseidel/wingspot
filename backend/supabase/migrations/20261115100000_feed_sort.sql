-- The feed can be sorted by the day of the check-in's event (what it always did) or by when it was checked in, so a
-- flight added later shows at the top. Each row also says the time to page with (cursor_time), which is the column the
-- feed is sorted by. An app that sends no sort gets the old order.
drop function public.get_feed(timestamptz, uuid, integer);
create function public.get_feed(before_time timestamptz default null, before_id uuid default null,
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
    and (before_time is null
         or (case when sort_by = 'created' then c.created_at else c.occurred_at end, c.id) < (before_time, before_id))
  order by case when sort_by = 'created' then c.created_at else c.occurred_at end desc, c.id desc
  limit least(greatest(coalesce(page_size, 30), 1), 50);
$$;
revoke execute on function public.get_feed(timestamptz, uuid, integer, text) from public;
grant execute on function public.get_feed(timestamptz, uuid, integer, text) to authenticated;
