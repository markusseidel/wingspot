-- Profile images: a public bucket, and everyone writes only in their own folder.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

select is((select public from storage.buckets where id = 'avatars'), true, 'the avatars bucket is public');
select is((select file_size_limit from storage.buckets where id = 'avatars'), 524288::bigint, 'files are at most 512 KB');
select is((select allowed_mime_types from storage.buckets where id = 'avatars'), '{image/jpeg}'::text[], 'only JPEG is accepted');

insert into auth.users (id, aud, role, email) values
  ('00000000-0000-0000-0000-000000000d01', 'authenticated', 'authenticated', 'avatar1@example.test'),
  ('00000000-0000-0000-0000-000000000d02', 'authenticated', 'authenticated', 'avatar2@example.test');
insert into storage.objects (bucket_id, name, owner_id) values
  ('avatars', '00000000-0000-0000-0000-000000000d02/avatar.jpg', '00000000-0000-0000-0000-000000000d02');

select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000d01', 'role', 'authenticated')::text, true);
set local role authenticated;
select lives_ok(
  $$ insert into storage.objects (bucket_id, name, owner_id) values ('avatars', '00000000-0000-0000-0000-000000000d01/avatar.jpg', '00000000-0000-0000-0000-000000000d01') $$,
  'you can upload your own image');
select throws_ok(
  $$ insert into storage.objects (bucket_id, name, owner_id) values ('avatars', '00000000-0000-0000-0000-000000000d02/other.jpg', '00000000-0000-0000-0000-000000000d01') $$,
  '42501', null, 'you cannot upload into someone else''s folder');
select is((select count(*)::int from storage.objects where bucket_id = 'avatars' and name like '00000000-0000-0000-0000-000000000d02/%'), 0, 'you cannot list other people''s folders');
select lives_ok(
  $$ update storage.objects set name = name where bucket_id = 'avatars' and name = '00000000-0000-0000-0000-000000000d01/avatar.jpg' $$,
  'you can replace your own image');
reset role;

-- Storage refuses direct deletes (the Storage API removes files), so the delete rule is checked as a policy.
select is((select count(*)::int from pg_policies where schemaname = 'storage' and tablename = 'objects'
  and policyname = 'avatars: own folder, delete' and cmd = 'DELETE'), 1, 'deleting is allowed only in your own folder');

select * from finish();
rollback;
