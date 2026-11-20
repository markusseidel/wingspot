-- A metric for the total distance of your flights, `distance_flown_km`, for badges that ask for it. The distance of each
-- flight is the one the server worked out when it was saved (distance_km). The badges that use it are not in this
-- repository; see backend/private/README.md.

-- The new metric is added to the badge evaluation in place, so the long function isn't copied again.
do $$
declare
  def text := pg_get_functiondef('private.badge_values(uuid)'::regprocedure);
  marker text := 'when ''checkins_total'' then';
begin
  if position(marker in def) = 0 then
    raise exception 'badge_values has no checkins_total metric to anchor on';
  end if;
  execute replace(def, marker,
    'when ''distance_flown_km'' then (select coalesce(sum(c.distance_km), 0) from public.checkins c '
    || 'where c.user_id = uid and c.kind = ''flown'') ' || marker);
end;
$$;
