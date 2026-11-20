-- A friend tagging you on a flight or an airport visit sends you a push (docs/FRIEND-TAGS.md, step 1b). It follows the
-- usual rules of notifications: not for yourself, not between people who blocked each other, at most 30 a day, and
-- one per person and check-in. A switch in the settings turns it off.

alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check
  check (kind in ('follow', 'salute', 'comment', 'checkin', 'tagged'));

alter table public.notification_prefs add column tagged boolean not null default true;
grant update (tagged) on public.notification_prefs to authenticated;

create or replace function private.queue_notification(to_user uuid, notify_kind text, from_user uuid, for_checkin uuid, text_snippet text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if to_user is null or to_user = from_user then return; end if;
  if private.is_blocked(to_user, from_user) then return; end if;
  if not coalesce((
    select case notify_kind when 'follow' then p.new_followers when 'salute' then p.salutes when 'comment' then p.comments
                     when 'checkin' then p.followed_checkins when 'tagged' then p.tagged end
    from public.notification_prefs p where p.user_id = to_user
  ), true) then return; end if;
  if not exists (
    select 1 from public.devices d where d.user_id = to_user and d.platform in ('ios', 'android') and d.push_token is not null
  ) then return; end if;
  if (select count(*) from public.notifications n
      where n.recipient = to_user and n.created_at > now() - interval '24 hours') >= 30 then return; end if;
  if notify_kind <> 'comment' and exists (
    select 1 from public.notifications n
    where n.recipient = to_user and n.kind = notify_kind and n.actor = from_user
      and n.checkin_id is not distinct from for_checkin and n.created_at > now() - interval '1 hour'
  ) then return; end if;
  insert into public.notifications (recipient, kind, actor, checkin_id, snippet)
  values (to_user, notify_kind, from_user, for_checkin, text_snippet);
end;
$$;

-- A new tag tells the tagged person. A failure here never stops the upload that made the tag.
create function private.notify_tag() returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_author uuid;
begin
  select c.user_id into v_author from public.checkins c where c.id = new.checkin_id;
  perform private.queue_notification(new.user_id, 'tagged', v_author, new.checkin_id, null);
  return null;
exception when others then
  raise warning 'tag notification failed: %', sqlerrm;
  return null;
end;
$$;
revoke execute on function private.notify_tag() from public, anon, authenticated;

create trigger checkin_tags_notify after insert on public.checkin_tags
  for each row execute function private.notify_tag();
