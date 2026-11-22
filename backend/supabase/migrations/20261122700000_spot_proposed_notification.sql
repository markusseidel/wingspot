-- Tell the people who can review places when a place is suggested (issue #279).
-- Until now only the author heard about a decision; a reviewer had to open "Review places" to find out that something
-- waits. A new notification kind, spot_proposed, goes to everyone with the review_spots permission (the founder, and
-- later moderators) except the author: an inbox note and a push. The snippet is the name of the place.

alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check
  check (kind in ('follow', 'salute', 'comment', 'checkin', 'tagged', 'mention', 'reply', 'comment_like', 'tag_copy', 'friend_badge',
                  'spot_approved', 'spot_rejected', 'spot_proposed'));

-- Two places suggested by the same person within the hour are two different things, so this kind skips the duplicate check.
do $$
declare
  v_def text := pg_get_functiondef('private.queue_notification(uuid, text, uuid, uuid, text)'::regprocedure);
  v_new text;
begin
  v_new := replace(v_def, '''spot_approved'', ''spot_rejected'') and exists (', '''spot_approved'', ''spot_rejected'', ''spot_proposed'') and exists (');
  if v_new = v_def then raise exception 'anchor not found in queue_notification'; end if;
  execute v_new;
end;
$$;

create function private.notify_spot_proposed() returns trigger language plpgsql security definer set search_path = '' as $$
declare
  reviewer record;
begin
  if new.status <> 'pending' then return null; end if;
  for reviewer in
    select distinct r.user_id from public.staff_roles r
    where private.has_permission(r.user_id, 'review_spots') and r.user_id is distinct from new.created_by
  loop
    perform private.queue_notification(reviewer.user_id, 'spot_proposed', new.created_by, null, new.name);
  end loop;
  return null;
exception when others then
  -- Telling reviewers must never stop a place from being suggested.
  raise warning 'notify_spot_proposed failed: %', sqlerrm;
  return null;
end;
$$;
revoke execute on function private.notify_spot_proposed() from public;

create trigger spotting_locations_notify_reviewers after insert on public.spotting_locations
  for each row execute function private.notify_spot_proposed();
