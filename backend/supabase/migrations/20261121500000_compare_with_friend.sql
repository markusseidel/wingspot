-- Compare with a friend (docs/SOCIAL-PLAN.md, feature 3): your numbers next to theirs, and what you share.
-- Only the check-ins the caller may see count on the other side, so nothing private leaks through a total or a list.
-- Hidden badges are not part of it.

-- Two lists of objects with a "key" each, split into what is in both, only in the first and only in the second.
create function private.split_sets(mine jsonb, theirs jsonb) returns jsonb
language sql immutable set search_path = '' as $$
  select jsonb_build_object(
    'common', coalesce((select jsonb_agg(m.v order by m.v ->> 'code') from jsonb_array_elements(mine) m(v)
                        where exists (select 1 from jsonb_array_elements(theirs) t(v) where t.v -> 'key' = m.v -> 'key')), '[]'::jsonb),
    'mine',   coalesce((select jsonb_agg(m.v order by m.v ->> 'code') from jsonb_array_elements(mine) m(v)
                        where not exists (select 1 from jsonb_array_elements(theirs) t(v) where t.v -> 'key' = m.v -> 'key')), '[]'::jsonb),
    'theirs', coalesce((select jsonb_agg(t.v order by t.v ->> 'code') from jsonb_array_elements(theirs) t(v)
                        where not exists (select 1 from jsonb_array_elements(mine) m(v) where m.v -> 'key' = t.v -> 'key')), '[]'::jsonb)
  );
$$;
revoke execute on function private.split_sets(jsonb, jsonb) from public, anon, authenticated;

-- The caller's numbers and lists against a friend's. Null when the person's profile can't be seen, or it is the caller.
create function public.compare_with(p_target uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_me uuid := auth.uid();
  v_result jsonb;
begin
  if v_me is null or p_target is null or p_target = v_me then return null; end if;
  if not private.can_view_profile_content(p_target) then return null; end if;

  with src as (
    select 'me'::text as who, c.kind, c.distance_km, c.airport_id, c.origin_id, c.destination_id, c.operator_id, c.type_icao
    from public.checkins c where c.user_id = v_me
    union all
    select 'them', c.kind, c.distance_km, c.airport_id, c.origin_id, c.destination_id, c.operator_id, c.type_icao
    from public.checkins c where c.user_id = p_target and private.can_view_checkin(c.id)
  ),
  ap as (
    select distinct s.who, a.id, coalesce(a.iata, a.icao) as code, a.name, a.country_code
    from src s cross join lateral unnest(array[s.airport_id, s.origin_id, s.destination_id]) x(id)
    join public.airports a on a.id = x.id
  ),
  cn as (select distinct who, country_code::text as code from ap where country_code is not null),
  op as (
    select distinct s.who, o.id, coalesce(o.iata, o.icao, o.name) as code, o.name
    from src s join public.operators o on o.id = s.operator_id
  ),
  ty as (
    select distinct s.who, t.icao_code as code, trim(coalesce(t.manufacturer, '') || ' ' || coalesce(t.model, '')) as name
    from src s join public.aircraft_types t on t.icao_code = s.type_icao
  ),
  lists as (
    select
      (select coalesce(jsonb_agg(jsonb_build_object('key', id, 'code', code, 'name', name)), '[]') from ap where who = 'me') as ap_me,
      (select coalesce(jsonb_agg(jsonb_build_object('key', id, 'code', code, 'name', name)), '[]') from ap where who = 'them') as ap_them,
      (select coalesce(jsonb_agg(jsonb_build_object('key', code, 'code', code)), '[]') from cn where who = 'me') as cn_me,
      (select coalesce(jsonb_agg(jsonb_build_object('key', code, 'code', code)), '[]') from cn where who = 'them') as cn_them,
      (select coalesce(jsonb_agg(jsonb_build_object('key', id, 'code', code, 'name', name)), '[]') from op where who = 'me') as op_me,
      (select coalesce(jsonb_agg(jsonb_build_object('key', id, 'code', code, 'name', name)), '[]') from op where who = 'them') as op_them,
      (select coalesce(jsonb_agg(jsonb_build_object('key', code, 'code', code, 'name', name)), '[]') from ty where who = 'me') as ty_me,
      (select coalesce(jsonb_agg(jsonb_build_object('key', code, 'code', code, 'name', name)), '[]') from ty where who = 'them') as ty_them
  ),
  counts as (
    select w.who,
      (select count(*) from src s where s.who = w.who and s.kind = 'flown') as flights,
      (select coalesce(sum(s.distance_km), 0) from src s where s.who = w.who and s.kind = 'flown') as distance_km,
      (select count(*) from ap where ap.who = w.who) as airports,
      (select count(*) from cn where cn.who = w.who) as countries,
      (select count(*) from op where op.who = w.who) as airlines,
      (select count(*) from ty where ty.who = w.who) as types
    from (values ('me'), ('them')) w(who)
  )
  select jsonb_build_object(
    'me', (select to_jsonb(c) - 'who' from counts c where c.who = 'me'),
    'them', (select to_jsonb(c) - 'who' from counts c where c.who = 'them'),
    'airports', private.split_sets(l.ap_me, l.ap_them),
    'countries', private.split_sets(l.cn_me, l.cn_them),
    'airlines', private.split_sets(l.op_me, l.op_them),
    'types', private.split_sets(l.ty_me, l.ty_them)
  ) into v_result
  from lists l;
  return v_result;
end;
$$;
revoke execute on function public.compare_with(uuid) from public, anon;
grant execute on function public.compare_with(uuid) to authenticated;
