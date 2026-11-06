-- Photos: the private bucket, who may touch which folder, and register_photo.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

insert into auth.users (id, aud, role, email) values
  ('00000000-0000-0000-0000-0000000000c1', 'authenticated', 'authenticated', 'photo-a@example.test'),
  ('00000000-0000-0000-0000-0000000000d1', 'authenticated', 'authenticated', 'photo-b@example.test');

create function pg_temp.as_user(uid text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true),
         set_config('role', 'authenticated', true);
$$;

select is((select public from storage.buckets where id = 'photos'), false, 'the photos bucket is private');
select is((select file_size_limit from storage.buckets where id = 'photos'), 3145728::bigint, 'photos are limited to 3 MB');
select is((select allowed_mime_types from storage.buckets where id = 'photos'), '{image/jpeg}'::text[], 'only JPEG is allowed');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000c1');
select is(public.sync_checkins('[{"id":"30000000-0000-0000-0000-000000000001","kind":"spotted","occurred_at":"2026-01-01T10:00:00Z","registration":"D-PHOT"}]'::jsonb) -> 'results' -> 0 ->> 'status',
          'stored', 'alice has a check-in');

-- Folders -----------------------------------------------------------------------------------
select lives_ok(
  $$ insert into storage.objects (bucket_id, name, owner) values
     ('photos', '00000000-0000-0000-0000-0000000000c1/30000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001.jpg',
      '00000000-0000-0000-0000-0000000000c1') $$,
  'alice can upload into her own folder'
);
select throws_ok(
  $$ insert into storage.objects (bucket_id, name, owner) values
     ('photos', '00000000-0000-0000-0000-0000000000d1/x/y.jpg', '00000000-0000-0000-0000-0000000000c1') $$,
  '42501', null, 'alice cannot upload into bob''s folder'
);

-- register_photo ------------------------------------------------------------------------------
select is(public.register_photo('40000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 800, 600),
          'stored', 'an uploaded photo is registered');
select is(public.register_photo('40000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 800, 600),
          'stored', 'registering it again is harmless');
select is(public.register_photo('40000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000001', 800, 600),
          'missing_file', 'a photo that was not uploaded is refused');
select is(public.register_photo('40000000-0000-0000-0000-000000000003', '30000000-0000-0000-0000-0000000000ff', 800, 600),
          'unknown_checkin', 'a photo for a check-in that does not exist is refused');

-- The limit is four photos per check-in
reset role;
insert into storage.objects (bucket_id, name, owner)
select 'photos', '00000000-0000-0000-0000-0000000000c1/30000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-00000000001' || n || '.jpg',
       '00000000-0000-0000-0000-0000000000c1' from generate_series(1, 4) n;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000c1');
select is(array_agg(public.register_photo(('40000000-0000-0000-0000-00000000001' || n)::uuid, '30000000-0000-0000-0000-000000000001', 1, 1) order by n),
          array['stored','stored','stored','too_many_photos'], 'the fifth photo is refused')
from generate_series(1, 4) n;

-- Bob can't see or use alice's things -----------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000000d1');
select is((select count(*)::int from storage.objects where bucket_id = 'photos'), 0, 'bob cannot see alice''s photos');
select is(public.register_photo('40000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 1, 1),
          'unknown_checkin', 'bob cannot attach photos to alice''s check-in');
select is((select count(*)::int from public.checkin_photos), 0, 'private check-ins keep their photo rows private too');

set local role anon;
select is((select count(*)::int from storage.objects where bucket_id = 'photos'), 0, 'anonymous visitors see no photos');
select throws_ok($$select public.register_photo(gen_random_uuid(), gen_random_uuid(), 1, 1)$$, '42501', null,
                 'anonymous visitors cannot register photos');
reset role;

select * from finish();
rollback;
