-- Profile images. One public bucket, one file per person: <user id>/avatar.jpg. Reading is public, like the name.
-- Only the owner may write in their own folder. The phone sends a 512 x 512 JPEG without camera or location data.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 524288, '{image/jpeg}');

-- Replacing a file reads it first, so the owner needs a read rule. Everyone else reads through the public address,
-- which does not go through this table, so nobody can list other people's folders.
create policy "avatars: own folder, read" on storage.objects for select to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "avatars: own folder, upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "avatars: own folder, replace" on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "avatars: own folder, delete" on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
