-- Check-in photos (milestone 5). Photos live in a private bucket, one folder per user, and are never listed
-- or read by anyone but their owner until sharing exists (milestone 7). The app uploads through the
-- checkins function, which acts as the user, so these policies are what keeps users out of each other's folders.
-- The phone removes location data before upload. The function refuses any JPEG that still carries metadata.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('photos', 'photos', false, 3145728, '{image/jpeg}');

create policy "photos: own folder, read" on storage.objects for select to authenticated
  using (bucket_id = 'photos' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "photos: own folder, upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'photos' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "photos: own folder, replace" on storage.objects for update to authenticated
  using (bucket_id = 'photos' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'photos' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- Ties an uploaded photo to one of the caller's check-ins. Repeating it for the same photo is harmless.
-- Returns 'stored', or a rejection code: 'unknown_checkin' (not uploaded yet, so try again later),
-- 'missing_file', 'too_many_photos' or 'id_taken'.
create function public.register_photo(photo_id uuid, checkin uuid, photo_width integer, photo_height integer)
returns text language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  v_path text;
  v_existing uuid;
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if not exists (select 1 from public.checkins c where c.id = checkin and c.user_id = uid) then
    return 'unknown_checkin';
  end if;

  v_path := uid::text || '/' || checkin::text || '/' || photo_id::text || '.jpg';
  select p.checkin_id into v_existing from public.checkin_photos p where p.id = photo_id;
  if found then
    return case when v_existing = checkin then 'stored' else 'id_taken' end;
  end if;

  if not exists (select 1 from storage.objects o where o.bucket_id = 'photos' and o.name = v_path) then
    return 'missing_file';
  end if;
  if (select count(*) from public.checkin_photos p where p.checkin_id = checkin) >= 4 then
    return 'too_many_photos';
  end if;

  insert into public.checkin_photos (id, checkin_id, storage_path, width, height, position)
  values (photo_id, checkin, v_path, photo_width, photo_height,
          (select count(*) from public.checkin_photos p where p.checkin_id = checkin));
  return 'stored';
end;
$$;
revoke execute on function public.register_photo(uuid, uuid, integer, integer) from public;
grant execute on function public.register_photo(uuid, uuid, integer, integer) to authenticated;
