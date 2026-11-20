-- Deleting a flight also deletes the two airport visits it created (departing at the origin, arriving at the
-- destination, at the flight's time), as the owner's apps do not link them to the flight. They are found the same way
-- as when the day of a flight is changed. A visit stays if another flight of the same user at the same time still
-- uses its airport. Spotting visits and visits at other times are never touched.
create or replace function public.delete_checkin(target uuid)
returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  flight public.checkins;
begin
  select * into flight from public.checkins where id = target and user_id = auth.uid() and kind = 'flown';
  if found then
    delete from public.checkins v
    where v.user_id = flight.user_id and v.kind = 'airport' and v.visit_context in ('departing', 'arriving')
      and v.occurred_at = flight.occurred_at and v.airport_id in (flight.origin_id, flight.destination_id)
      and not exists (
        select 1 from public.checkins other
        where other.user_id = flight.user_id and other.kind = 'flown' and other.id <> flight.id
          and other.occurred_at = flight.occurred_at and v.airport_id in (other.origin_id, other.destination_id));
  end if;
  delete from public.checkins where id = target and user_id = auth.uid();
end;
$$;
