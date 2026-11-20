-- Deleting a check-in takes back what it earned: badge levels, their progress and the XP follow the check-ins that are left.
-- Until now a badge level never went down, so a badge earned by a check-in that was later deleted stayed.
-- Only deleting a check-in lowers levels. Every other evaluation (uploads, opening the badges page) still keeps the
-- level you have, even if a badge's rule changes later. A badge that falls back to level 0 loses its unlock date, so
-- earning it again counts as a new unlock and is celebrated again.

create function private.evaluate_badges(uid uuid, allow_decrease boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  r record;
  old_level integer;
  unlocked jsonb := '[]'::jsonb;
  new_xp integer;
begin
  for r in
    select b.id, b.name, b.description, b.category, b.kind, v.value,
           (select count(*) from unnest(b.levels) as l where v.value >= l)::integer as new_level
    from private.badge_values(uid) v
    join public.badges b on b.id = v.badge_id
    order by b.position
  loop
    select coalesce(ub.level, 0) into old_level
    from public.user_badges ub where ub.user_id = uid and ub.badge_id = r.id;
    old_level := coalesce(old_level, 0);

    insert into public.user_badges (user_id, badge_id, level, progress, unlocked_at)
    values (uid, r.id,
            nullif(case when allow_decrease then r.new_level else greatest(old_level, r.new_level) end, 0),
            r.value::integer,
            case when r.new_level > old_level then now() end)
    on conflict (user_id, badge_id) do update
      set progress = excluded.progress,
          level = excluded.level,
          unlocked_at = case when allow_decrease and r.new_level = 0 then null
                             else coalesce(excluded.unlocked_at, public.user_badges.unlocked_at) end;

    if r.new_level > old_level then
      unlocked := unlocked || jsonb_build_object(
        'id', r.id, 'level', r.new_level, 'previous_level', old_level,
        'name', r.name, 'description', r.description, 'category', r.category, 'kind', r.kind);
    end if;
  end loop;

  -- XP is a function of the data, so repeating this never double counts.
  select (10 * count(*) + 15 * count(distinct aircraft_id) + 30 * count(distinct type_icao)
          + 40 * count(distinct airport_id))::integer
  into new_xp
  from private.checkin_facts(uid);
  new_xp := new_xp + coalesce((
    select sum(50 * ub.level * (ub.level + 1) / 2)::integer
    from public.user_badges ub where ub.user_id = uid and ub.level is not null), 0);
  update public.profiles set xp = new_xp where id = uid;

  return jsonb_build_object('badges_unlocked', unlocked, 'xp', new_xp, 'level', private.xp_level(new_xp));
end;
$$;
revoke execute on function private.evaluate_badges(uuid, boolean) from public, anon, authenticated;

-- The usual evaluation keeps levels, as before.
create or replace function private.evaluate_badges(uid uuid) returns jsonb
language sql security definer set search_path = '' as $$
  select private.evaluate_badges(uid, false);
$$;

-- Deleting one of your check-ins re-evaluates your badges. A failure there never stops the delete.
create or replace function public.delete_checkin(target uuid)
returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  flight public.checkins;
  removed integer;
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
  get diagnostics removed = row_count;
  if removed > 0 then
    begin
      perform private.evaluate_badges(auth.uid(), true);
    exception when others then
      raise warning 'badge evaluation failed: %', sqlerrm;
    end;
  end if;
end;
$$;
