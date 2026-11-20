-- Friends on flights and airport visits (issue #182, docs/FRIEND-TAGS.md). The author of a check-in tags up to 8 mutual
-- friends. A tagged person can see that one check-in, can leave it for good, and can switch off being tagged.

create table public.checkin_tags (
  checkin_id uuid not null references public.checkins on delete cascade,
  user_id    uuid not null references public.profiles on delete cascade,
  created_at timestamptz not null default now(),
  primary key (checkin_id, user_id)
);
create index checkin_tags_user_idx on public.checkin_tags (user_id);

-- A person who left a check-in is not added to it again by a later upload of the author.
create table public.checkin_tag_removals (
  checkin_id uuid not null references public.checkins on delete cascade,
  user_id    uuid not null references public.profiles on delete cascade,
  primary key (checkin_id, user_id)
);
create index checkin_tag_removals_user_idx on public.checkin_tag_removals (user_id);

alter table public.profiles add column allow_tags boolean not null default true;
grant select (allow_tags) on public.profiles to anon, authenticated;
grant update (allow_tags) on public.profiles to authenticated;

alter table public.checkin_tags enable row level security;
alter table public.checkin_tag_removals enable row level security;
grant select on public.checkin_tags to authenticated;
-- Nobody writes tags directly. The functions below do it, after their checks.

-- Whether the caller is tagged on this check-in by an author who is still a friend and not blocked.
create function private.is_tagged_on(checkin uuid, author uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.checkin_tags t where t.checkin_id = checkin and t.user_id = auth.uid())
     and coalesce(private.are_friends(auth.uid(), author), false)
     and not coalesce(private.is_blocked(auth.uid(), author), true);
$$;
grant execute on function private.is_tagged_on(uuid, uuid) to anon, authenticated;

-- A tagged person sees the check-in they are tagged on, whatever its visibility.
create policy "read if tagged" on public.checkins for select to authenticated
  using (private.is_tagged_on(id, user_id));

-- Photos, comments and the like follow the check-in.
create or replace function private.can_view_checkin(target uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((
    select private.can_view_checkin_row(c.user_id, c.visibility, c.occurred_at) or private.is_tagged_on(c.id, c.user_id)
    from public.checkins c where c.id = target
  ), false);
$$;

-- Who can see a tag: everyone who can see the check-in.
create policy "read if check-in visible" on public.checkin_tags for select to authenticated
  using (private.can_view_checkin(checkin_id));

-- Replaces the tags of the author's own check-in with these people, ignoring everyone who may not be tagged: not a
-- mutual friend, blocked, tags switched off, left the check-in, and anyone beyond 8. Does nothing for someone else's id.
create function private.set_tags(author uuid, checkin uuid, tagged jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare
  wanted uuid[];
begin
  if not exists (select 1 from public.checkins c where c.id = checkin and c.user_id = author) then return; end if;
  if tagged is null or jsonb_typeof(tagged) <> 'array' then return; end if;
  select coalesce(array_agg(p.id), '{}') into wanted
  from (
    select p.id from (select distinct (e.value #>> '{}')::uuid as id from jsonb_array_elements(tagged) e) given
    join public.profiles p on p.id = given.id
    where p.id <> author and p.allow_tags
      and private.are_friends(author, p.id) and not private.is_blocked(author, p.id)
      and not exists (select 1 from public.checkin_tag_removals r where r.checkin_id = checkin and r.user_id = p.id)
    limit 8
  ) p;
  delete from public.checkin_tags t where t.checkin_id = checkin and not (t.user_id = any(wanted));
  insert into public.checkin_tags (checkin_id, user_id)
  select checkin, w from unnest(wanted) w
  on conflict do nothing;
end;
$$;
revoke execute on function private.set_tags(uuid, uuid, jsonb) from public, anon, authenticated;

-- An upload may carry `with`, a list of user ids, which replaces the tags. Without it the tags stay. Patched in place
-- so the long function isn't copied again.
do $$
declare
  def text := pg_get_functiondef('public.sync_checkins(jsonb)'::regprocedure);
  marker text := E'      results := results || jsonb_build_object(''id'', v_id, ''status'', ''stored'');';
begin
  if position(marker in def) = 0 then
    raise exception 'sync_checkins has no result line to anchor on';
  end if;
  execute replace(def, marker,
    E'      if item -> ''with'' is not null then perform private.set_tags(uid, v_id, item -> ''with''); end if;\n' || marker);
end;
$$;

-- The tags of these check-ins, for the ones the caller can see. At most 200 check-ins per call.
create function public.get_checkin_tags(ids uuid[])
returns table (checkin_id uuid, user_id uuid, username text, display_name text)
language sql stable security invoker set search_path = '' as $$
  select t.checkin_id, t.user_id, p.username, p.display_name
  from public.checkin_tags t
  join public.profiles p on p.id = t.user_id
  where t.checkin_id = any(ids[1:200])
  order by t.created_at, t.user_id;
$$;
revoke execute on function public.get_checkin_tags(uuid[]) from public;
grant execute on function public.get_checkin_tags(uuid[]) to authenticated;

-- The caller leaves a check-in they are tagged on, for good.
create function public.remove_my_tag(checkin uuid) returns void
language sql volatile security definer set search_path = '' as $$
  with gone as (
    delete from public.checkin_tags t where t.checkin_id = checkin and t.user_id = auth.uid() returning t.checkin_id, t.user_id
  )
  insert into public.checkin_tag_removals (checkin_id, user_id) select checkin_id, user_id from gone
  on conflict do nothing;
$$;
revoke execute on function public.remove_my_tag(uuid) from public;
grant execute on function public.remove_my_tag(uuid) to authenticated;

-- The caller's mutual friends who allow being tagged: the people the picker offers.
create function public.get_taggable_friends()
returns table (id uuid, username text, display_name text)
language sql stable security definer set search_path = '' as $$
  select p.id, p.username, p.display_name
  from public.follows a
  join public.follows b on b.follower = a.followee and b.followee = a.follower
  join public.profiles p on p.id = a.followee
  where a.follower = auth.uid() and p.allow_tags and not coalesce(private.is_blocked(auth.uid(), p.id), true)
  order by lower(coalesce(p.display_name, p.username)), p.id;
$$;
revoke execute on function public.get_taggable_friends() from public;
grant execute on function public.get_taggable_friends() to authenticated;

-- Unfriending (and so blocking, which ends follows) removes the tags between the two people.
create function private.end_tags_on_unfollow() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  delete from public.checkin_tags t using public.checkins c
  where t.checkin_id = c.id
    and ((c.user_id = old.follower and t.user_id = old.followee) or (c.user_id = old.followee and t.user_id = old.follower));
  return null;
end;
$$;
revoke execute on function private.end_tags_on_unfollow() from public, anon, authenticated;
create trigger follows_end_tags after delete on public.follows
  for each row execute function private.end_tags_on_unfollow();
