-- Delete a single photo of your own check-in, and really remove its file (issue #272, docs/DELETE-PHOTO-PLAN.md).
--
-- The row goes first, so the photo is gone for everybody at once. A trigger puts the file's path in a queue, because a
-- stored file can only be removed through the Storage API: the checkins function empties the queue with the service
-- key. If that fails, the path stays in the queue and goes with the next run. The same queue also catches the files of
-- check-ins that are deleted (their photo rows go by cascade), which used to stay in storage.

create table private.photo_files_to_remove (
  path text primary key,
  queued_at timestamptz not null default now()
);

create function private.queue_photo_file() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into private.photo_files_to_remove (path) values (old.storage_path) on conflict do nothing;
  return null;
end;
$$;
create trigger checkin_photos_queue_file after delete on public.checkin_photos
  for each row execute function private.queue_photo_file();

-- Deletes one photo of the caller's own check-in. Deleting one that doesn't exist, or isn't yours, does nothing.
create function public.delete_photo(photo uuid) returns void
language sql volatile security definer set search_path = '' as $$
  delete from public.checkin_photos p
  using public.checkins c
  where p.id = photo and c.id = p.checkin_id and c.user_id = auth.uid();
$$;
revoke execute on function public.delete_photo(uuid) from public, anon;
grant execute on function public.delete_photo(uuid) to authenticated;

-- For the function only (service role): the files waiting to be removed. A path that has a photo row again (the same
-- photo was uploaded again after it was deleted) is dropped from the queue and not returned, so a live file is never removed.
create function public.queued_photo_files(max_files integer default 100) returns setof text
language plpgsql volatile security definer set search_path = '' as $$
begin
  delete from private.photo_files_to_remove q
  where exists (select 1 from public.checkin_photos p where p.storage_path = q.path);
  return query select q.path from private.photo_files_to_remove q order by q.queued_at limit max_files;
end;
$$;
revoke execute on function public.queued_photo_files(integer) from public, anon, authenticated;
grant execute on function public.queued_photo_files(integer) to service_role;

-- For the function only: these files are gone from storage.
create function public.photo_files_removed(paths text[]) returns void
language sql volatile security definer set search_path = '' as $$
  delete from private.photo_files_to_remove where path = any (paths);
$$;
revoke execute on function public.photo_files_removed(text[]) from public, anon, authenticated;
grant execute on function public.photo_files_removed(text[]) to service_role;

-- A new photo goes after the highest position, not after the count: with a photo deleted from the middle the count
-- would give a position that is already taken.
do $$
declare
  def text := pg_get_functiondef('public.register_photo(uuid, uuid, integer, integer)'::regprocedure);
  old_text text := E'(select count(*) from public.checkin_photos p where p.checkin_id = checkin));';
  new_text text := E'(select coalesce(max(p.position) + 1, 0) from public.checkin_photos p where p.checkin_id = checkin));';
begin
  if position(old_text in def) = 0 then
    raise exception 'register_photo has no position expression to anchor on';
  end if;
  execute replace(def, old_text, new_text);
end;
$$;

-- Files of check-ins that were deleted before this existed: stored files with no photo row (older than an hour, so an
-- upload that is happening right now is left alone). They go with the first run of the function.
insert into private.photo_files_to_remove (path)
select o.name from storage.objects o
where o.bucket_id = 'photos' and o.created_at < now() - interval '1 hour'
  and not exists (select 1 from public.checkin_photos p where p.storage_path = o.name)
on conflict do nothing;
