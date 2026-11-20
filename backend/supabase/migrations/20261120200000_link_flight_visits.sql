-- An airport visit that a flight created is linked to that flight. The apps send the flight's id with each visit, so
-- deleting a flight deletes exactly its visits and changing its day moves exactly those, whatever their time says.
-- There is no foreign key on purpose: a visit can arrive before its flight, or next to a flight the server refused, and
-- that must never fail an upload. A trigger does the cleanup instead.
-- Visits without the link (made before this, or by an app that doesn't send it) are still found by their time and
-- airports, as before.
alter table public.checkins add column flight_id uuid;
create index checkins_flight_id_idx on public.checkins (flight_id) where flight_id is not null;

-- Link the visits that exist: the departing visit at the origin and the arriving visit at the destination, at the
-- flight's time. A visit that two flights would claim goes to the one with the smaller id.
update public.checkins v set flight_id = f.id
from (
  select distinct on (v2.id) v2.id as visit_id, f2.id
  from public.checkins v2
  join public.checkins f2 on f2.user_id = v2.user_id and f2.kind = 'flown' and f2.occurred_at = v2.occurred_at
    and ((v2.visit_context = 'departing' and v2.airport_id = f2.origin_id)
      or (v2.visit_context = 'arriving' and v2.airport_id = f2.destination_id))
  where v2.kind = 'airport'
  order by v2.id, f2.id
) f
where v.id = f.visit_id;

-- The upload takes the link for visits. It is set when the visit is stored and never changed by a later upload.
do $$
declare
  def text := pg_get_functiondef('public.sync_checkins(jsonb)'::regprocedure);
  columns_marker text := 'visit_context, origin_id, destination_id';
  values_marker text := 'v_airport, v_context,';
begin
  if position(columns_marker in def) = 0 or position(values_marker in def) = 0 then
    raise exception 'sync_checkins has no insert to anchor on';
  end if;
  execute replace(replace(def, columns_marker, 'visit_context, flight_id, origin_id, destination_id'),
    values_marker, 'v_airport, v_context, case when v_kind = ''airport'' then nullif(item ->> ''flight_id'', '''')::uuid end,');
end;
$$;

-- Deleting a flight deletes the visits linked to it.
create function private.delete_flight_visits() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  delete from public.checkins v where v.flight_id = old.id and v.user_id = old.user_id and v.kind = 'airport';
  return null;
end;
$$;
revoke execute on function private.delete_flight_visits() from public, anon, authenticated;

create trigger checkins_delete_visits after delete on public.checkins
  for each row when (old.kind = 'flown') execute function private.delete_flight_visits();

-- delete_checkin only has to look for visits without a link. Linked ones go with the trigger above.
create or replace function public.delete_checkin(target uuid)
returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  flight public.checkins;
begin
  select * into flight from public.checkins where id = target and user_id = auth.uid() and kind = 'flown';
  if found then
    delete from public.checkins v
    where v.user_id = flight.user_id and v.kind = 'airport' and v.flight_id is null
      and v.visit_context in ('departing', 'arriving')
      and v.occurred_at = flight.occurred_at and v.airport_id in (flight.origin_id, flight.destination_id)
      and not exists (
        select 1 from public.checkins other
        where other.user_id = flight.user_id and other.kind = 'flown' and other.id <> flight.id
          and other.occurred_at = flight.occurred_at and v.airport_id in (other.origin_id, other.destination_id));
  end if;
  delete from public.checkins where id = target and user_id = auth.uid();
end;
$$;

-- Changing the day of a flight moves its linked visits, and the unlinked ones that match by time and airports.
create or replace function private.move_flight_visits() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.checkins v set occurred_at = new.occurred_at
  where v.user_id = new.user_id and v.kind = 'airport' and v.visit_context in ('departing', 'arriving')
    and (v.flight_id = new.id
         or (v.flight_id is null and v.occurred_at = old.occurred_at and v.airport_id in (new.origin_id, new.destination_id)));
  return null;
end;
$$;
