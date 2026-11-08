-- Milestone 11b: the airports with the most check-ins lately, among check-ins the caller may see.
-- Runs as the caller, so the check-in rules decide what counts (own, friends, public with the author's delay and
-- private profile, nothing when blocked). Flights don't count, and neither does a sensitive aircraft of someone
-- else, so a number can't give away that such an aircraft was at an airport.
create function public.get_active_airports(days integer default 7, max_results integer default 10)
returns table (airport_id integer, airport_code text, airport_name text, city text, checkins integer, people integer)
language sql stable security invoker set search_path = '' as $$
  select
    ap.id, coalesce(ap.iata, ap.icao), ap.name, ap.city,
    count(*)::integer, count(distinct c.user_id)::integer
  from public.checkins c
  join public.airports ap on ap.id = c.airport_id
  left join public.aircraft a on a.id = c.aircraft_id
  where c.kind <> 'flown'
    and c.occurred_at > now() - make_interval(days => least(greatest(coalesce(days, 7), 1), 90))
    and not coalesce(a.is_sensitive and c.user_id <> auth.uid(), false)
  group by ap.id, ap.iata, ap.icao, ap.name, ap.city
  order by count(*) desc, ap.name
  limit least(greatest(coalesce(max_results, 10), 1), 30);
$$;
revoke execute on function public.get_active_airports(integer, integer) from public;
grant execute on function public.get_active_airports(integer, integer) to authenticated;
