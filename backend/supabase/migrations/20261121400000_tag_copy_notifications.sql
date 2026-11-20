-- Shared flights, polish (docs/SOCIAL-PLAN.md, feature 6). When a tagged friend adds your flight or visit to their own
-- logbook, you are told ("Max added your flight to their logbook"), and your check-in page lists who did.

-- A copy counts as the same switch as being tagged.
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
                     when 'mention' then p.comments when 'comment_like' then p.salutes
                     when 'tag_copy' then p.tagged end
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

-- The server keeps the link to the original only when the copier really was tagged (valid_tag_source), so a row that
-- carries one is a real copy. A failure here never stops the upload.
create function private.notify_tag_copy() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform private.queue_notification(
    (select c.user_id from public.checkins c where c.id = new.source_checkin_id), 'tag_copy', new.user_id, new.source_checkin_id, null);
  return null;
exception when others then
  raise warning 'notify_tag_copy failed: %', sqlerrm;
  return null;
end;
$$;
revoke execute on function private.notify_tag_copy() from public, anon, authenticated;
create trigger checkins_notify_tag_copy after insert on public.checkins
  for each row when (new.source_checkin_id is not null) execute function private.notify_tag_copy();

-- The friends who added this check-in of the caller's to their own logbook. Empty for anyone but the author.
create function public.get_checkin_copies(p_checkin uuid)
returns table (user_id uuid, username text, display_name text)
language sql stable security definer set search_path = '' as $$
  select c.user_id, p.username, p.display_name
  from public.checkins c
  join public.profiles p on p.id = c.user_id
  where auth.uid() is not null
    and c.source_checkin_id = p_checkin
    and exists (select 1 from public.checkins o where o.id = p_checkin and o.user_id = auth.uid())
    and not private.is_blocked(auth.uid(), c.user_id)
  order by c.created_at;
$$;
revoke execute on function public.get_checkin_copies(uuid) from public, anon;
grant execute on function public.get_checkin_copies(uuid) to authenticated;
