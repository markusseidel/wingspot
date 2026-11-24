-- Backdated check-ins (#312): a sighting or an airport check-in can have a date (and optionally a time) in the past, and the
-- date can be corrected later.
--
--  * checkins.time_known: false for a date-only entry, so no app shows a made-up 12:00. Default true (old rows, flights, old apps).
--  * sync_checkins: a repeated upload of a sighting or an airport visit now takes the new occurred_at (and time_known when sent),
--    except for an airport visit of a flight (it follows the flight). Moving an airport visit moves its sightings by the same step.
--    A moved check-in makes the person's badges be worked out again, with levels allowed to go down. Dates before 1990 are refused.
--  * The readers of check-in lists return time_known next to occurred_at.

alter table public.checkins add column time_known boolean not null default true;
-- Check-ins have column grants (the location is never granted); the readers that run as the caller need this one.
grant select (time_known) on public.checkins to anon, authenticated;

-- 1. sync_checkins
do $$
declare
  def text := pg_get_functiondef('public.sync_checkins(jsonb)'::regprocedure);
  before text := def;
begin
  -- variables
  def := replace(def, E'  v_owner uuid;\n', E'  v_owner uuid;\n  v_time_known boolean;\n  v_old timestamptz;\n  v_moved boolean := false;\n');
  -- the lowest date
  def := replace(def, 'if v_occurred is null or v_occurred > now() + interval ''1 day'' then',
                 'if v_occurred is null or v_occurred > now() + interval ''1 day'' or v_occurred < timestamptz ''1990-01-01 00:00:00+00'' then');
  -- the flag, and the time the row has now (before the upsert)
  def := replace(def, E'      v_aircraft := null;\n      if v_registration is not null then',
                 E'      v_time_known := case when v_kind = ''flown'' then true else coalesce((item ->> ''time_known'')::boolean, true) end;\n' ||
                 E'      select c.occurred_at into v_old from public.checkins c where c.id = v_id and c.user_id = uid;\n\n' ||
                 E'      v_aircraft := null;\n      if v_registration is not null then');
  def := replace(def, 'distance_km, location, visibility)', 'distance_km, location, visibility, time_known)');
  def := replace(def, E'              v_visibility)\n      on conflict (id) do update',
                 E'              v_visibility, v_time_known)\n      on conflict (id) do update');
  def := replace(def, 'set occurred_at = case when checkins.kind = ''flown'' then excluded.occurred_at else checkins.occurred_at end,',
                 'set occurred_at = case when checkins.kind = ''flown'' or (checkins.kind in (''spotted'', ''airport'') and not private.is_flight_visit(checkins.id))' ||
                 E'\n                                then excluded.occurred_at else checkins.occurred_at end,\n' ||
                 E'            time_known = case when checkins.kind in (''spotted'', ''airport'') and item ? ''time_known'' and not private.is_flight_visit(checkins.id)\n' ||
                 E'                              then excluded.time_known else checkins.time_known end,');
  -- after the upsert: the sightings of a moved visit follow it, and the badges are worked out again
  def := replace(def, E'      get diagnostics v_inserted = row_count;\n',
                 E'      get diagnostics v_inserted = row_count;\n\n' ||
                 E'      if v_old is not null and v_old <> v_occurred and v_kind in (''spotted'', ''airport'') and not private.is_flight_visit(v_id) then\n' ||
                 E'        v_moved := true;\n' ||
                 E'        if v_kind = ''airport'' then\n' ||
                 E'          update public.checkins x set occurred_at = x.occurred_at + (v_occurred - v_old)\n' ||
                 E'          where x.visit_id = v_id and x.user_id = uid and x.kind = ''spotted'';\n' ||
                 E'        end if;\n' ||
                 E'      end if;\n');
  def := replace(def, 'engine := private.evaluate_badges(uid);',
                 'engine := case when v_moved then private.evaluate_badges(uid, true) else private.evaluate_badges(uid) end;');
  if def = before or position('v_moved' in def) = 0 or position('time_known = case' in def) = 0
     or position('1990-01-01' in def) = 0 or position('v_visibility, v_time_known' in def) = 0
     or position('select c.occurred_at into v_old' in def) = 0 or position('evaluate_badges(uid, true) else' in def) = 0
     or position('distance_km, location, visibility, time_known' in def) = 0 or position('v_time_known boolean' in def) = 0 then
    raise exception 'sync_checkins did not match the expected text';
  end if;
  execute def;
end
$$;

-- 2. The readers: time_known comes right after occurred_at, in the result and in the select list. The functions are replaced
--    (the result type changes) and get the grants they had.
do $$
declare
  f record;
  def text;
  anon_ok boolean;
  auth_ok boolean;
begin
  for f in
    select p.oid, p.proname, pg_get_function_identity_arguments(p.oid) as args
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('get_airport_checkins', 'get_checkin', 'get_feed', 'get_my_checkins', 'get_person_checkins',
                        'get_registration_checkins', 'get_spot_sightings', 'get_type_checkins', 'get_visit_sightings')
  loop
    def := pg_get_functiondef(f.oid);
    anon_ok := has_function_privilege('anon', f.oid, 'execute');
    auth_ok := has_function_privilege('authenticated', f.oid, 'execute');
    def := regexp_replace(def, 'occurred_at timestamp with time zone,', 'occurred_at timestamp with time zone, time_known boolean,');
    -- the first "<alias>.occurred_at," is the select list (the result type line has no alias)
    def := regexp_replace(def, '([a-z]+)\.occurred_at,', '\1.occurred_at, \1.time_known,');
    if position('time_known boolean' in def) = 0 or position('.time_known,' in def) = 0 then
      raise exception '% did not match the expected text', f.proname;
    end if;
    execute format('drop function public.%I(%s)', f.proname, f.args);
    execute def;
    execute format('revoke execute on function public.%I(%s) from public, anon, authenticated', f.proname, f.args);
    if anon_ok then execute format('grant execute on function public.%I(%s) to anon', f.proname, f.args); end if;
    if auth_ok then execute format('grant execute on function public.%I(%s) to authenticated', f.proname, f.args); end if;
  end loop;
end
$$;
