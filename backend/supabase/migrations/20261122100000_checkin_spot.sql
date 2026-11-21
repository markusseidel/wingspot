-- What the check-in page needs about spotting locations (docs/SPOTTING-LOCATIONS-PLAN.md, PR 2: read side).
-- For a visit: the place it was at (if any) and how many aircraft were linked to it. For a sighting: the visit it
-- belongs to and that visit's place. Nothing is returned for a check-in the caller may not see.
create function public.get_checkin_spot(p_id uuid) returns jsonb
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
    on s.id = case when c.kind = 'airport' then c.spot_location_id else v.spot_location_id end
   and (s.status = 'approved' or s.created_by = auth.uid())
  where auth.uid() is not null and c.id = p_id and private.can_view_checkin(c.id)
    and (c.kind = 'airport' or (c.kind = 'spotted' and v.id is not null));
$$;

revoke execute on function public.get_checkin_spot(uuid) from public, anon;
grant execute on function public.get_checkin_spot(uuid) to authenticated;
