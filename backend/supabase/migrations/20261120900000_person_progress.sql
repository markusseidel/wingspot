-- A person's level and earned badges, for their profile page. It follows the rule for the rest of a profile
-- (private.can_view_profile_content): everyone for a public profile, friends for a private one, nobody if blocked.
-- The answer has the shape of get_my_progress. Hidden badges are left out, so a surprise stays one: a friend sees the
-- badges they could have seen in the list, not the ones that are meant to be found. Returns null when the caller
-- may not see the profile.
create function public.get_person_progress(target uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  their_xp integer;
  their_level integer;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if not coalesce(private.can_view_profile_content(target), false) then
    return null;
  end if;

  select p.xp into their_xp from public.profiles p where p.id = target;
  if not found then
    return null;
  end if;
  their_level := private.xp_level(their_xp);

  return jsonb_build_object(
    'xp', their_xp, 'level', their_level,
    'xp_for_level', 50 * their_level * (their_level - 1),
    'xp_for_next_level', 50 * (their_level + 1) * their_level,
    'badges', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', b.id, 'name', b.name, 'description', b.description, 'category', b.category,
               'kind', b.kind, 'hidden', false, 'levels', to_jsonb(b.levels),
               'value', coalesce(ub.progress, 0), 'level', ub.level,
               'unlocked_at', ub.unlocked_at) order by b.position), '[]'::jsonb)
      from public.badges b
      join public.user_badges ub on ub.badge_id = b.id and ub.user_id = target and ub.level > 0
      where not b.hidden
        and (b.valid_from is null or b.valid_from <= now()) and (b.valid_until is null or b.valid_until > now())),
    'hidden_remaining', 0);
end;
$$;
revoke execute on function public.get_person_progress(uuid) from public, anon;
grant execute on function public.get_person_progress(uuid) to authenticated;
