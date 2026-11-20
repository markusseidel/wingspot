-- Invite friends (docs/SOCIAL-PLAN.md, feature 1). Everyone has a personal invite code. Sharing it (as a code, a
-- wingspot://invite/CODE link or a QR code) lets a friend follow you in one step, and the app suggests people you may know.

alter table public.profiles add column invite_code text unique;
alter table public.profiles add column allow_suggestions boolean not null default true;
grant select (allow_suggestions) on public.profiles to authenticated;
grant update (allow_suggestions) on public.profiles to authenticated;
-- The code itself is never readable through the table: only get_my_invite_code returns it, and only to its owner.

-- 8 characters without look-alikes (no 0 O 1 I).
create function private.new_invite_code() returns text
language plpgsql volatile set search_path = '' as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  result text := '';
begin
  for i in 1..8 loop
    result := result || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
  end loop;
  return result;
end;
$$;
revoke execute on function private.new_invite_code() from public, anon, authenticated;

-- Your invite code. It is made the first time it is asked for.
create function public.get_my_invite_code() returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_code text;
begin
  if auth.uid() is null then raise exception 'not signed in' using errcode = '42501'; end if;
  select p.invite_code into v_code from public.profiles p where p.id = auth.uid();
  if v_code is not null then return v_code; end if;
  loop
    begin
      v_code := private.new_invite_code();
      update public.profiles set invite_code = v_code where id = auth.uid() and invite_code is null;
      select p.invite_code into v_code from public.profiles p where p.id = auth.uid();
      return v_code;
    exception when unique_violation then
      -- another person has this code: try again
    end;
  end loop;
end;
$$;

-- A new code, so the old link stops working.
create function public.reset_my_invite_code() returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_code text;
begin
  if auth.uid() is null then raise exception 'not signed in' using errcode = '42501'; end if;
  loop
    begin
      v_code := private.new_invite_code();
      update public.profiles set invite_code = v_code where id = auth.uid();
      return v_code;
    exception when unique_violation then
    end;
  end loop;
end;
$$;

-- Who owns a code: id, username and name, so the app can ask "Follow Anna?". Null for an unknown code, a blocked
-- person or yourself.
create function public.invite_owner(p_code text) returns table (id uuid, username text, display_name text)
language sql stable security definer set search_path = '' as $$
  select p.id, p.username, p.display_name
  from public.profiles p
  where auth.uid() is not null
    and p.invite_code = upper(trim(p_code))
    and p.id <> auth.uid()
    and not private.is_blocked(auth.uid(), p.id);
$$;

-- Follows the owner of a code. Returns them, or nothing for an unknown code.
create function public.follow_by_code(p_code text) returns table (id uuid, username text, display_name text)
language plpgsql security definer set search_path = '' as $$
declare
  v_owner uuid;
begin
  if auth.uid() is null then raise exception 'not signed in' using errcode = '42501'; end if;
  select o.id into v_owner from public.invite_owner(p_code) o;
  if v_owner is null then return; end if;
  insert into public.follows (follower, followee) values (auth.uid(), v_owner) on conflict do nothing;
  return query select p.id, p.username, p.display_name from public.profiles p where p.id = v_owner;
end;
$$;

-- People you may know: followed by at least two of the people you follow, or tagged with you on a flight, and not
-- followed by you yet. Not blocked people, nor anyone who switched suggestions off.
create function public.people_you_may_know(p_limit integer default 20)
returns table (user_id uuid, username text, display_name text, reason text, mutual integer)
language sql stable security definer set search_path = '' as $$
  with me as (select auth.uid() as id),
  mutual as (
    select f2.followee as uid, count(*)::integer as n
    from public.follows f1
    join public.follows f2 on f2.follower = f1.followee
    where f1.follower = (select id from me)
    group by f2.followee
  ),
  tagged as (
    select distinct t2.user_id as uid
    from public.checkin_tags t1
    join public.checkin_tags t2 on t2.checkin_id = t1.checkin_id and t2.user_id <> t1.user_id
    where t1.user_id = (select id from me)
    union
    select distinct c.user_id
    from public.checkin_tags t join public.checkins c on c.id = t.checkin_id
    where t.user_id = (select id from me)
    union
    select distinct t.user_id
    from public.checkins c join public.checkin_tags t on t.checkin_id = c.id
    where c.user_id = (select id from me)
  ),
  candidates as (
    select coalesce(m.uid, t.uid) as uid, coalesce(m.n, 0) as n, (t.uid is not null) as was_tagged
    from mutual m full join tagged t on t.uid = m.uid
    where coalesce(m.n, 2) >= 2 or t.uid is not null
  )
  select p.id, p.username, p.display_name,
    case when c.was_tagged then 'tagged' else 'mutual' end, c.n
  from candidates c
  join public.profiles p on p.id = c.uid
  where (select id from me) is not null
    and p.id <> (select id from me)
    and p.allow_suggestions
    and not exists (select 1 from public.follows f where f.follower = (select id from me) and f.followee = p.id)
    and not private.is_blocked((select id from me), p.id)
  order by c.was_tagged desc, c.n desc, p.username
  limit greatest(least(coalesce(p_limit, 20), 50), 1);
$$;

revoke execute on function public.get_my_invite_code() from public, anon;
revoke execute on function public.reset_my_invite_code() from public, anon;
revoke execute on function public.invite_owner(text) from public, anon;
revoke execute on function public.follow_by_code(text) from public, anon;
revoke execute on function public.people_you_may_know(integer) from public, anon;
grant execute on function public.get_my_invite_code() to authenticated;
grant execute on function public.reset_my_invite_code() to authenticated;
grant execute on function public.invite_owner(text) to authenticated;
grant execute on function public.follow_by_code(text) to authenticated;
grant execute on function public.people_you_may_know(integer) to authenticated;
