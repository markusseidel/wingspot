-- Time-of-day badges (Night Owl, Early Bird and any badge with the metric local_hour_between) count only check-ins where
-- the person really was at the airport (issue #277).
--
-- "Local time" of a check-in is estimated from the airport's longitude. For a person who is at the airport that is right.
-- A flight is logged at some moment (often now, or midday of an earlier day) and stores two airport visits with that same
-- moment, so the visits got the "local time" of a faraway airport: a flight to Asia logged at 18:00 in Germany counted as
-- 02:00 and earned Night Owl. A flight and its two visits say nothing about the hour at the airport, so they do not count
-- for these badges. Spotting and standalone airport check-ins still do.

do $$
declare
  def text := pg_get_functiondef('private.badge_values(uuid)'::regprocedure);
  old_text text := E'when ''local_hour_between'' then (\n        select count(*) from f\n        where case when';
  new_text text := E'when ''local_hour_between'' then (\n        select count(*) from f\n        where f.checkin_id not in (select c2.id from public.checkins c2\n                                   where c2.user_id = uid and (c2.kind = ''flown'' or private.is_flight_visit(c2.id)))\n          and case when';
begin
  if position(old_text in def) = 0 then
    raise exception 'badge_values has no local_hour_between to anchor on';
  end if;
  execute replace(def, old_text, new_text);
end;
$$;

-- Whoever got such a badge from a flight loses it: every person who holds a badge with this metric is evaluated again,
-- with levels allowed to go down (as after deleting a check-in).
do $$
declare
  r record;
begin
  for r in
    select distinct ub.user_id
    from public.user_badges ub
    join public.badges b on b.id = ub.badge_id
    where b.rule ->> 'metric' = 'local_hour_between' and ub.level > 0
  loop
    perform private.evaluate_badges(r.user_id, true);
  end loop;
end;
$$;
