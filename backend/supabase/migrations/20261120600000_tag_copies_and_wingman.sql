-- Add a friend's flight or visit to your own logbook, and the Wingman badge (docs/FRIEND-TAGS.md, step 2).
-- A check-in made from a tag carries the id of the check-in it was copied from. The server only keeps the link when the
-- caller really is tagged on that check-in and has no copy of it yet, so a check-in can't be copied twice.

alter table public.checkins add column source_checkin_id uuid;
create index checkins_source_idx on public.checkins (source_checkin_id) where source_checkin_id is not null;

create function private.valid_tag_source(uid uuid, source uuid, own uuid) returns uuid
language sql stable security definer set search_path = '' as $$
  select source
  where source is not null
    and exists (select 1 from public.checkin_tags t where t.checkin_id = source and t.user_id = uid)
    and not exists (select 1 from public.checkins c where c.user_id = uid and c.source_checkin_id = source and c.id <> own);
$$;
revoke execute on function private.valid_tag_source(uuid, uuid, uuid) from public, anon, authenticated;

-- The upload takes `source_checkin_id`. Patched in place so the long function isn't copied again.
do $$
declare
  def text := pg_get_functiondef('public.sync_checkins(jsonb)'::regprocedure);
  columns_marker text := 'visit_context, flight_id, origin_id';
  values_marker text := E'nullif(item ->> ''flight_id'', '''')::uuid end,';
begin
  if position(columns_marker in def) = 0 or position(values_marker in def) = 0 then
    raise exception 'sync_checkins has no insert to anchor on';
  end if;
  execute replace(replace(def, columns_marker, 'visit_context, flight_id, source_checkin_id, origin_id'),
    values_marker, values_marker
      || E' private.valid_tag_source(uid, nullif(item ->> ''source_checkin_id'', '''')::uuid, v_id),');
end;
$$;

-- Wingman: check-ins done together with a friend, as the author or as the tagged friend.
do $$
declare
  def text := pg_get_functiondef('private.badge_values(uuid)'::regprocedure);
  marker text := 'when ''checkins_total'' then';
begin
  if position(marker in def) = 0 then
    raise exception 'badge_values has no checkins_total metric to anchor on';
  end if;
  execute replace(def, marker,
    'when ''checkins_together'' then (select count(*) from ('
    || 'select c.id from public.checkins c join public.checkin_tags t on t.checkin_id = c.id where c.user_id = uid '
    || 'union select t.checkin_id from public.checkin_tags t where t.user_id = uid) together) ' || marker);
end;
$$;

insert into public.badges (id, name, description, category, kind, rule, levels, hidden, valid_from, position) values
  ('wingman', '{"en": "Wingman", "de": "Wingman"}'::jsonb,
   '{"en": "Check in together with friends: tag them, or be tagged.", "de": "Checke gemeinsam mit Freunden ein: markiere sie oder werde markiert."}'::jsonb,
   'milestones', 'leveled', '{"metric": "checkins_together"}'::jsonb, '{1,5,10,25}', false, null, 40);
