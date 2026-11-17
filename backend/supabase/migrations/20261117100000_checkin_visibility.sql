-- Who sees one check-in, set apart from the account's sharing choice. A check-in the person set by hand is marked
-- visibility_custom, and "apply to existing" in the account's sharing setting leaves those alone.
alter table public.checkins add column visibility_custom boolean not null default false;

-- The caller's own check-in: who can see it, and whether that was set by hand. Nothing if it isn't theirs.
create function public.get_checkin_visibility(target uuid)
returns table (visibility text, is_custom boolean)
language sql stable security definer set search_path = '' as $$
  select c.visibility, c.visibility_custom from public.checkins c where c.id = target and c.user_id = auth.uid();
$$;
revoke execute on function public.get_checkin_visibility(uuid) from public;
grant execute on function public.get_checkin_visibility(uuid) to authenticated;

-- Sets who can see one of the caller's own check-ins. A null `new_visibility` goes back to the account's sharing choice
-- (and the check-in follows later changes of it again). Returns the visibility now, or null when the check-in doesn't
-- exist or isn't the caller's, so a repeated request is safe.
create function public.set_checkin_visibility(target uuid, new_visibility text)
returns text
language plpgsql volatile security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  result text;
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if new_visibility is not null and new_visibility not in ('public', 'followers', 'friends', 'private') then
    raise exception 'invalid_visibility' using errcode = '22023';
  end if;
  update public.checkins c
     set visibility = coalesce(new_visibility, (select p.default_visibility from public.profiles p where p.id = uid), 'private'),
         visibility_custom = new_visibility is not null
   where c.id = target and c.user_id = uid
  returning c.visibility into result;
  return result;
end;
$$;
revoke execute on function public.set_checkin_visibility(uuid, text) from public;
grant execute on function public.set_checkin_visibility(uuid, text) to authenticated;

-- "Apply to existing" changes the earlier check-ins that follow the account's choice, not the ones set by hand.
create or replace function public.set_sharing(new_default text, apply_to_existing boolean default false)
returns integer language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  changed integer := 0;
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if new_default is null or new_default not in ('public', 'followers', 'friends', 'private') then
    raise exception 'invalid_visibility' using errcode = '22023';
  end if;
  update public.profiles set default_visibility = new_default where id = uid;
  if apply_to_existing then
    update public.checkins set visibility = new_default
     where user_id = uid and visibility <> new_default and not visibility_custom;
    get diagnostics changed = row_count;
  end if;
  return changed;
end;
$$;
