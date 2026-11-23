-- Deleting a single photo of your own check-in, and the queue of files to remove (issue #272).
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

insert into auth.users (id, aud, role, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated', 'delphoto1@example.test'),
  ('00000000-0000-0000-0000-0000000000a2', 'authenticated', 'authenticated', 'delphoto2@example.test');

-- A check-in of alice with three photos (rows and stored files)
insert into public.checkins (id, user_id, kind, occurred_at) values
  ('d0000000-0000-7000-8000-000000000001', '00000000-0000-0000-0000-0000000000a1', 'spotted', now() - interval '1 day');
insert into storage.objects (bucket_id, name) values
  ('photos', '00000000-0000-0000-0000-0000000000a1/d0000000-0000-7000-8000-000000000001/d1000000-0000-7000-8000-000000000001.jpg'),
  ('photos', '00000000-0000-0000-0000-0000000000a1/d0000000-0000-7000-8000-000000000001/d1000000-0000-7000-8000-000000000002.jpg'),
  ('photos', '00000000-0000-0000-0000-0000000000a1/d0000000-0000-7000-8000-000000000001/d1000000-0000-7000-8000-000000000003.jpg'),
  ('photos', '00000000-0000-0000-0000-0000000000a1/d0000000-0000-7000-8000-000000000001/d1000000-0000-7000-8000-000000000004.jpg');
insert into public.checkin_photos (id, checkin_id, storage_path, width, height, position)
select ('d1000000-0000-7000-8000-00000000000' || n)::uuid, 'd0000000-0000-7000-8000-000000000001',
       '00000000-0000-0000-0000-0000000000a1/d0000000-0000-7000-8000-000000000001/d1000000-0000-7000-8000-00000000000' || n || '.jpg',
       100, 100, n - 1
from generate_series(1, 3) n;

-- Someone else cannot delete it
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000a2', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);
select public.delete_photo('d1000000-0000-7000-8000-000000000002');
select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
select is((select count(*) from public.checkin_photos where checkin_id = 'd0000000-0000-7000-8000-000000000001'), 3::bigint, 'another person cannot delete the photo');
select is((select count(*) from private.photo_files_to_remove), 0::bigint, 'and nothing is queued');

-- The owner can
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000a1', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);
select public.delete_photo('d1000000-0000-7000-8000-000000000002');
select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
select is((select count(*) from public.checkin_photos where checkin_id = 'd0000000-0000-7000-8000-000000000001'), 2::bigint, 'the owner deletes the photo');
select is((select count(*) from public.checkins where id = 'd0000000-0000-7000-8000-000000000001'), 1::bigint, 'the check-in stays');
select is((select array_agg(path) from private.photo_files_to_remove),
          array['00000000-0000-0000-0000-0000000000a1/d0000000-0000-7000-8000-000000000001/d1000000-0000-7000-8000-000000000002.jpg'],
          'the file of the photo is queued for removal');

-- Deleting it again is harmless
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000a1', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);
select lives_ok($$select public.delete_photo('d1000000-0000-7000-8000-000000000002')$$, 'deleting a photo that is gone does nothing');

-- A new photo goes after the highest position, not after the count (positions 0 and 2 are left)
select is(public.register_photo('d1000000-0000-7000-8000-000000000004', 'd0000000-0000-7000-8000-000000000001', 100, 100), 'stored', 'a new photo is stored');
select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
select is((select position::integer from public.checkin_photos where id = 'd1000000-0000-7000-8000-000000000004'), 3, 'and gets the position after the highest');

-- The queue is for the function only
select ok(not has_function_privilege('authenticated', 'public.queued_photo_files(integer)', 'execute'), 'signed-in people cannot read the queue');
select ok(not has_function_privilege('authenticated', 'public.photo_files_removed(text[])', 'execute'), 'nor empty it');
select ok(has_function_privilege('service_role', 'public.queued_photo_files(integer)', 'execute'), 'the service role can read it');

-- The queue gives the path, and drops one whose photo is back (uploaded again after the delete)
select is((select count(*) from public.queued_photo_files()), 1::bigint, 'the queue lists the deleted photo file');
insert into public.checkin_photos (id, checkin_id, storage_path, width, height, position) values
  ('d1000000-0000-7000-8000-000000000002', 'd0000000-0000-7000-8000-000000000001',
   '00000000-0000-0000-0000-0000000000a1/d0000000-0000-7000-8000-000000000001/d1000000-0000-7000-8000-000000000002.jpg', 100, 100, 9);
select is((select count(*) from public.queued_photo_files()), 0::bigint, 'a file whose photo is back is not removed');
select is((select count(*) from private.photo_files_to_remove), 0::bigint, 'and leaves the queue');

-- Deleting a whole check-in queues the files of all its photos (4 are there: 1, 2, 3 and 4)
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000a1', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);
select public.delete_checkin('d0000000-0000-7000-8000-000000000001');
select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
select is((select count(*) from private.photo_files_to_remove), 4::bigint, 'deleting a check-in queues the files of its photos');
select public.photo_files_removed(array(select path from private.photo_files_to_remove));
select is((select count(*) from private.photo_files_to_remove), 0::bigint, 'removed files leave the queue');

select * from finish();
rollback;
