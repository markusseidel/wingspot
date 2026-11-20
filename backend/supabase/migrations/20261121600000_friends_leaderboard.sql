-- Friends leaderboard (docs/SOCIAL-PLAN.md, feature 4). You and the people you follow, ranked by distance, flights,
-- countries or airports, this year or all time. Nobody is on someone else's board unless they switched it on
-- ("Show me on friends' leaderboards", off by default). Other people count only with the check-ins you may see.

alter table public.profiles add column show_on_leaderboard boolean not null default false;
grant select (show_on_leaderboard) on public.profiles to authenticated;
grant update (show_on_leaderboard) on public.profiles to authenticated;

-- metric: distance, flights, countries or airports. period: year (the current calendar year) or all.
create function public.get_leaderboard(p_metric text, p_period text default 'all')
returns table (user_id uuid, username text, display_name text, value bigint, is_me boolean)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_me uuid := auth.uid();
  v_since timestamptz;
begin
  if v_me is null then raise exception 'not signed in' using errcode = '42501'; end if;
  if p_metric not in ('distance', 'flights', 'countries', 'airports') then
    raise exception 'unknown metric' using errcode = '22023';
  end if;
  if p_period not in ('year', 'all') then
    raise exception 'unknown period' using errcode = '22023';
  end if;
  v_since := case p_period when 'year' then date_trunc('year', now()) else '-infinity'::timestamptz end;

  return query
  with people as (
    select v_me as id
    union
    select f.followee
    from public.follows f
    join public.profiles p on p.id = f.followee
    where f.follower = v_me and p.show_on_leaderboard
      and private.can_view_profile_content(f.followee)
      and not private.is_blocked(v_me, f.followee)
  ),
  src as (
    select c.user_id, c.kind, c.distance_km, c.airport_id, c.origin_id, c.destination_id
    from public.checkins c
    join people pe on pe.id = c.user_id
    where c.occurred_at >= v_since
      and (c.user_id = v_me or private.can_view_checkin(c.id))
  ),
  airports_seen as (
    select distinct s.user_id as uid, a.id, a.country_code
    from src s cross join lateral unnest(array[s.airport_id, s.origin_id, s.destination_id]) x(id)
    join public.airports a on a.id = x.id
  ),
  scores as (
    select pe.id as uid,
      case p_metric
        when 'distance' then coalesce((select sum(s.distance_km) from src s where s.user_id = pe.id and s.kind = 'flown'), 0)
        when 'flights' then (select count(*) from src s where s.user_id = pe.id and s.kind = 'flown')
        when 'airports' then (select count(*) from airports_seen a where a.uid = pe.id)
        else (select count(distinct a.country_code) from airports_seen a where a.uid = pe.id)
      end::bigint as score
    from people pe
  )
  select sc.uid, pr.username, pr.display_name, sc.score, sc.uid = v_me
  from scores sc join public.profiles pr on pr.id = sc.uid
  order by sc.score desc, pr.username
  limit 50;
end;
$$;
revoke execute on function public.get_leaderboard(text, text) from public, anon;
grant execute on function public.get_leaderboard(text, text) to authenticated;
