-- Badges in the feed: a check-in's card shows the badges that check-in earned, so friends see "Jan earned Gate Hopper".
-- A badge level is tied to the check-in the person made when they reached it: the newest one at that moment. Badges that
-- came from something else (a friend tagging them, an anniversary) are tied to their newest check-in too, so there is
-- always a card to show them on. Badges earned before this stay without one and show nowhere.
-- Hidden badges never show: they are meant to be found, not announced.

-- evaluate_badges stores the check-in of an unlock. Patched in place, so the long function isn't copied again.
do $$
declare
  def text := pg_get_functiondef('private.evaluate_badges(uuid, boolean)'::regprocedure);
  a text := E'  new_xp integer;\nbegin\n  for r in';
  b text := 'insert into public.user_badges (user_id, badge_id, level, progress, unlocked_at)';
  c text := E'case when r.new_level > old_level then now() end)';
  d text := E'      set progress = excluded.progress,';
begin
  if position(a in def) = 0 or position(b in def) = 0 or position(c in def) = 0 or position(d in def) = 0 then
    raise exception 'evaluate_badges has no place to anchor on';
  end if;
  def := replace(def, a, E'  new_xp integer;\n  v_checkin uuid;\nbegin\n'
    || E'  select c.id into v_checkin from public.checkins c where c.user_id = uid order by c.created_at desc, c.id desc limit 1;\n  for r in');
  def := replace(def, b, 'insert into public.user_badges (user_id, badge_id, level, progress, unlocked_at, checkin_id)');
  def := replace(def, c, E'case when r.new_level > old_level then now() end,\n            case when r.new_level > old_level then v_checkin end)');
  def := replace(def, d, E'      set checkin_id = case when allow_decrease and r.new_level = 0 then null\n'
    || E'                            else coalesce(excluded.checkin_id, public.user_badges.checkin_id) end,\n'
    || E'      progress = excluded.progress,');
  execute def;
end;
$$;

-- The badges of these check-ins that the caller may see, for the feed. At most 200 check-ins at a time.
create function public.get_checkin_badges(ids uuid[])
returns table (checkin_id uuid, badge_id text, name jsonb, category text, levels integer[], level integer)
language sql stable security definer set search_path = '' as $$
  select ub.checkin_id, b.id, b.name, b.category, b.levels, ub.level
  from public.user_badges ub
  join public.badges b on b.id = ub.badge_id
  where ub.checkin_id = any ((ids)[1:200])
    and ub.level > 0
    and not b.hidden
    and private.can_view_checkin(ub.checkin_id)
  order by ub.checkin_id, b.position;
$$;
revoke execute on function public.get_checkin_badges(uuid[]) from public, anon;
grant execute on function public.get_checkin_badges(uuid[]) to authenticated;
