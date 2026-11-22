-- Day-based badges (weekends, streaks, busy day, anniversary, same registration on different days, dates) no longer take
-- the "local time" of a faraway airport for a flight (issue #277, follow-up).
--
-- A flight is logged at some moment, and its two airport visits carry that same moment. The visit at a faraway airport got
-- that airport's local time, so a flight logged on a Friday evening in Germany counted as a Saturday in Asia and extended
-- weekend streaks. Now a flight and its visits take the person's own time: the longitude of their home airport (UTC when
-- they have none). Spotting and standalone airport check-ins keep the time at the airport.

do $$
declare
  def text := pg_get_functiondef('private.checkin_facts(uuid)'::regprocedure);
  old_text text := E'(c.occurred_at at time zone ''UTC'') + make_interval(hours => round(\n           coalesce(extensions.st_x(ap.location::extensions.geometry),\n                    extensions.st_x(c.location::extensions.geometry), 0) / 15)::integer)';
  new_text text := E'(c.occurred_at at time zone ''UTC'') + make_interval(hours => round(\n           case when c.kind = ''flown'' or private.is_flight_visit(c.id)\n                then coalesce((select extensions.st_x(h.location::extensions.geometry) from public.profiles p\n                               join public.airports h on h.id = p.home_airport where p.id = uid), 0)\n                else coalesce(extensions.st_x(ap.location::extensions.geometry),\n                              extensions.st_x(c.location::extensions.geometry), 0) end / 15)::integer)';
begin
  if position(old_text in def) = 0 then
    raise exception 'checkin_facts has no local time expression to anchor on';
  end if;
  execute replace(def, old_text, new_text);
end;
$$;

-- Whoever holds a day-based badge is evaluated again, with levels allowed to go down (as after deleting a check-in).
do $$
declare
  r record;
begin
  for r in
    select distinct ub.user_id
    from public.user_badges ub
    join public.badges b on b.id = ub.badge_id
    where b.rule ->> 'metric' in ('streak_weekends', 'streak_days', 'checkins_in_one_day', 'anniversary',
                                  'same_registration_days', 'same_registration_airport_days', 'checkins_on_date')
      and ub.level > 0
      and exists (select 1 from public.checkins c where c.user_id = ub.user_id and c.kind = 'flown')
  loop
    perform private.evaluate_badges(r.user_id, true);
  end loop;
end;
$$;
