-- Mentions and likes on comments (docs/SOCIAL-PLAN.md, feature 5).
-- A comment can mention friends with @username. A mentioned person gets a notification and the name becomes a link.
-- A reply is a comment that starts with the @username of the person it answers, so it is a mention too.
-- A comment can be saluted like a check-in; the author is told.

-- IMPORTANT: neither table has a foreign key to profiles. With one, comments and profiles would be linked a second way
-- (comments -> comment_mentions -> profiles), and the embed `comments?select=...,profiles(username)` that every installed
-- app sends would fail as ambiguous (PostgREST PGRST201). The rows of a deleted person are removed by a trigger instead.

-- Who a comment mentions ---------------------------------------------------------------------------------------
create table public.comment_mentions (
  comment_id uuid not null references public.comments on delete cascade,
  user_id    uuid not null,
  primary key (comment_id, user_id)
);
create index comment_mentions_user_idx on public.comment_mentions (user_id);
alter table public.comment_mentions enable row level security;  -- no policies and no grants: only the functions below

-- Salutes on comments ------------------------------------------------------------------------------------------
create table public.comment_salutes (
  comment_id uuid not null references public.comments on delete cascade,
  user_id    uuid not null,
  created_at timestamptz not null default now(),
  primary key (comment_id, user_id)
);
create index comment_salutes_user_idx on public.comment_salutes (user_id);
alter table public.comment_salutes enable row level security;

-- Deleting an account removes what it mentioned or saluted.
create function private.forget_comment_marks() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  delete from public.comment_mentions where user_id = old.id;
  delete from public.comment_salutes where user_id = old.id;
  return null;
end;
$$;
revoke execute on function private.forget_comment_marks() from public, anon, authenticated;
create trigger profiles_forget_comment_marks after delete on public.profiles
  for each row execute function private.forget_comment_marks();

-- The two new kinds follow the switches the person already has: a mention like a comment, a comment salute like a salute.
create or replace function private.queue_notification(to_user uuid, notify_kind text, from_user uuid, for_checkin uuid, text_snippet text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_push boolean;
begin
  if to_user is null or to_user = from_user then return; end if;
  if private.is_blocked(to_user, from_user) then return; end if;
  if notify_kind <> 'comment' and exists (
    select 1 from public.notifications n
    where n.recipient = to_user and n.kind = notify_kind and n.actor = from_user
      and n.checkin_id is not distinct from for_checkin and n.created_at > now() - interval '1 hour'
  ) then return; end if;

  v_push := coalesce((
    select case notify_kind when 'follow' then p.new_followers when 'salute' then p.salutes when 'comment' then p.comments
                     when 'checkin' then p.followed_checkins when 'tagged' then p.tagged
                     when 'mention' then p.comments when 'comment_like' then p.salutes end
    from public.notification_prefs p where p.user_id = to_user
  ), true);
  if v_push then
    v_push := exists (
      select 1 from public.devices d where d.user_id = to_user and d.platform in ('ios', 'android') and d.push_token is not null
    );
  end if;
  if v_push then
    v_push := (select count(*) from public.notifications n
               where n.recipient = to_user and not n.silent and n.created_at > now() - interval '24 hours') < 30;
  end if;

  insert into public.notifications (recipient, kind, actor, checkin_id, snippet, silent, sent_at)
  values (to_user, notify_kind, from_user, for_checkin, text_snippet, not v_push, case when v_push then null else now() end);
end;
$$;

-- Reads the @names of a new comment. Only mutual friends of the author count, who may see the check-in, at most 5.
-- Anyone else is left out silently. A failure here never stops the comment.
create function private.record_mentions() returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_owner uuid;
  v_visibility text;
  v_occurred timestamptz;
  v_person uuid;
begin
  if position('@' in new.body) = 0 then return null; end if;
  select c.user_id, c.visibility, c.occurred_at into v_owner, v_visibility, v_occurred
  from public.checkins c where c.id = new.checkin_id;
  if v_owner is null then return null; end if;

  for v_person in
    select p.id
    from public.profiles p
    where p.username in (
      select m[1] from regexp_matches(lower(new.body), '(?<![a-z0-9_])@([a-z0-9_]{3,30})', 'g') m
    )
      and p.id <> new.user_id
      and private.are_friends(new.user_id, p.id)
      and not private.is_blocked(new.user_id, p.id)
      and (
        private.can_view_checkin_row_as(p.id, v_owner, v_visibility, v_occurred)
        or exists (select 1 from public.checkin_tags t where t.checkin_id = new.checkin_id and t.user_id = p.id)
      )
    order by p.username
    limit 5
  loop
    insert into public.comment_mentions (comment_id, user_id) values (new.id, v_person) on conflict do nothing;
    perform private.queue_notification(v_person, 'mention', new.user_id, new.checkin_id, left(new.body, 80));
  end loop;
  return null;
exception when others then
  raise warning 'record_mentions failed: %', sqlerrm;
  return null;
end;
$$;
revoke execute on function private.record_mentions() from public, anon, authenticated;
create trigger comments_mentions after insert on public.comments
  for each row execute function private.record_mentions();

-- Salute or un-salute a comment. Only for comments on check-ins the caller may see, not by or for a blocked person.
create function public.set_comment_salute(p_comment uuid, p_on boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_checkin uuid;
  v_author uuid;
  v_new integer;
begin
  if auth.uid() is null then raise exception 'not signed in' using errcode = '42501'; end if;
  select c.checkin_id, c.user_id into v_checkin, v_author from public.comments c where c.id = p_comment;
  if v_checkin is null or not private.can_view_checkin(v_checkin) or private.is_blocked(auth.uid(), v_author) then return; end if;
  if p_on then
    insert into public.comment_salutes (comment_id, user_id) values (p_comment, auth.uid()) on conflict do nothing;
    get diagnostics v_new = row_count;
    if v_new > 0 then
      perform private.queue_notification(v_author, 'comment_like', auth.uid(), v_checkin, null);
    end if;
  else
    delete from public.comment_salutes where comment_id = p_comment and user_id = auth.uid();
  end if;
end;
$$;

-- Salutes and mentions of the comments of one check-in, for the ones the caller may see. The people the caller blocked
-- (or who blocked them) are left out of the mentions.
create function public.get_comment_extras(p_checkin uuid)
returns table (comment_id uuid, salutes integer, saluted boolean, mentions jsonb)
language sql stable security definer set search_path = '' as $$
  select c.id,
    (select count(*)::integer from public.comment_salutes s where s.comment_id = c.id),
    exists (select 1 from public.comment_salutes s where s.comment_id = c.id and s.user_id = auth.uid()),
    coalesce((
      select jsonb_agg(jsonb_build_object('id', p.id, 'username', p.username) order by p.username)
      from public.comment_mentions m join public.profiles p on p.id = m.user_id
      where m.comment_id = c.id and not private.is_blocked(auth.uid(), m.user_id)
    ), '[]'::jsonb)
  from public.comments c
  where auth.uid() is not null and c.checkin_id = p_checkin and private.can_view_checkin(p_checkin);
$$;

revoke execute on function public.set_comment_salute(uuid, boolean) from public, anon;
revoke execute on function public.get_comment_extras(uuid) from public, anon;
grant execute on function public.set_comment_salute(uuid, boolean) to authenticated;
grant execute on function public.get_comment_extras(uuid) to authenticated;
