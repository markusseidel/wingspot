-- Access rules, tested as each kind of viewer. Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

-- Setup as the database owner --------------------------------------------------------------
insert into auth.users (id, aud, role, email) values
  ('00000000-0000-0000-0000-00000000000a', 'authenticated', 'authenticated', 'alice@example.test'),
  ('00000000-0000-0000-0000-00000000000b', 'authenticated', 'authenticated', 'bob@example.test'),
  ('00000000-0000-0000-0000-00000000000c', 'authenticated', 'authenticated', 'carol@example.test'),
  ('00000000-0000-0000-0000-00000000000d', 'authenticated', 'authenticated', 'dave@example.test'),
  ('00000000-0000-0000-0000-00000000000e', 'authenticated', 'authenticated', 'eve@example.test'),
  ('00000000-0000-0000-0000-00000000000f', 'authenticated', 'authenticated', 'frank@example.test');

select is((select count(*)::int from public.profiles where id::text like '00000000-0000-0000-0000-00000000000_'), 6, 'sign-up creates a profile');
select is((select count(*)::int from public.notification_prefs where user_id::text like '00000000-0000-0000-0000-00000000000_'), 6, 'sign-up creates notification settings');

insert into public.airports (id, icao, iata, name, country_code, continent, location)
  values (1, 'EDDF', 'FRA', 'Frankfurt', 'DE', 'EU', 'POINT(8.57 50.03)');

-- dave is private, frank delays posts by an hour, alice has a home airport.
update public.profiles set is_private = true where id = '00000000-0000-0000-0000-00000000000d';
update public.profiles set post_delay_minutes = 60 where id = '00000000-0000-0000-0000-00000000000f';
update public.profiles set home_airport = 1
  where id in ('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000d');

-- alice <-> bob and bob <-> dave and bob <-> frank are friends. carol follows alice one way.
insert into public.follows (follower, followee) values
  ('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000b'),
  ('00000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-00000000000a'),
  ('00000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-00000000000d'),
  ('00000000-0000-0000-0000-00000000000d', '00000000-0000-0000-0000-00000000000b'),
  ('00000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-00000000000f'),
  ('00000000-0000-0000-0000-00000000000f', '00000000-0000-0000-0000-00000000000b'),
  ('00000000-0000-0000-0000-00000000000c', '00000000-0000-0000-0000-00000000000a'),
  ('00000000-0000-0000-0000-00000000000e', '00000000-0000-0000-0000-00000000000a'),
  ('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000e');

insert into public.blocks (blocker, blocked)
  values ('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000e');
select is(
  (select count(*)::int from public.follows
   where '00000000-0000-0000-0000-00000000000e' in (follower, followee)),
  0, 'a block removes follows in both directions'
);

insert into public.checkins (id, user_id, kind, occurred_at, visibility, location) values
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', 'spotted', now() - interval '1 day', 'public', 'POINT(8.5 50.0)'),
  ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000a', 'spotted', now() - interval '1 day', 'friends', null),
  ('10000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-00000000000a', 'spotted', now() - interval '1 day', 'private', null),
  ('10000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-00000000000d', 'spotted', now() - interval '1 day', 'public', null),
  ('10000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-00000000000f', 'spotted', now() - interval '2 hours', 'public', null),
  ('10000000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-00000000000f', 'spotted', now() - interval '10 minutes', 'public', null);

insert into public.entitlements (user_id, entitlement, store, product_id, original_transaction_id, status)
  values ('00000000-0000-0000-0000-00000000000a', 'pro', 'app_store', 'pro_yearly', 'secret-transaction', 'active');

insert into public.salutes (user_id, checkin_id) values
  ('00000000-0000-0000-0000-00000000000e', '10000000-0000-0000-0000-000000000001');
insert into public.comments (checkin_id, user_id, body) values
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000e', 'from eve'),
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000b', 'from bob'),
  ('10000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-00000000000a', 'on private');

insert into public.spotting_locations (airport_id, name, status) values
  (1, 'Approved', 'approved'), (1, 'Pending', 'pending');

-- Schema-wide guarantees ------------------------------------------------------------------
select is(
  (select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity
     and c.relname <> 'spatial_ref_sys'),
  0, 'every public table has RLS enabled'
);
select ok(
  not exists (select 1 from information_schema.column_privileges
              where table_schema = 'public' and table_name = 'checkins' and column_name = 'location'
                and grantee in ('anon', 'authenticated', 'PUBLIC')),
  'no client role has any privilege on checkins.location'
);
select ok(
  not exists (select 1 from information_schema.role_table_grants
              where table_schema = 'public' and table_name in ('store_events', 'reports')
                and grantee in ('anon', 'authenticated', 'PUBLIC')),
  'store_events and reports have no client grants'
);

select is(
  (select string_agg(p.proname::text, ',' order by p.proname::text)
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute')
     and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')),
  'get_profile',
  'get_profile is the only function in public that anon can execute'
);
select is(
  (select string_agg(p.proname::text, ',' order by p.proname::text)
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and has_function_privilege('authenticated', p.oid, 'execute')
     and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')),
  'export_my_data,get_active_airports,get_airport_activity,get_airport_checkins,get_blocks,get_checkin,get_feed,get_my_progress,get_person_checkins,get_profile,get_registration_checkins,get_type_activity,get_type_checkins,register_device,register_photo,report,set_sharing,sync_checkins',
  'only export_my_data, get_active_airports, get_airport_activity, get_airport_checkins, get_blocks, get_checkin, get_feed, get_my_progress, get_person_checkins, get_profile, get_registration_checkins, get_type_activity, get_type_checkins, register_device, register_photo, report, set_sharing and sync_checkins are callable by signed-in users'
);

-- Anonymous visitor -----------------------------------------------------------------------
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

select results_eq(
  $$ select id from public.checkins order by id $$,
  $$ values ('10000000-0000-0000-0000-000000000001'::uuid), ('10000000-0000-0000-0000-000000000005'::uuid) $$,
  'anon sees only public, undelayed check-ins of public profiles'
);
select is((select count(*)::int from public.airports), 1, 'anon can read airports');
select is((select count(*)::int from public.app_config), 1, 'anon can read config');
select is((select count(*)::int from public.spotting_locations), 1, 'anon sees only approved spotting locations');
select throws_ok($$ select location from public.checkins $$, '42501', null, 'anon cannot read raw GPS');
select throws_ok($$ select * from public.devices $$, '42501', null, 'anon cannot read devices');
select throws_ok($$ select * from public.entitlements $$, '42501', null, 'anon cannot read entitlements');
select throws_ok(
  $$ select public.register_device(gen_random_uuid(), 'ios', '1.0') $$,
  '42501', null, 'anon cannot register a device'
);
select throws_ok($$ select private.handle_new_user() $$, '42501', null, 'anon cannot call trigger functions');
select throws_ok(
  $$ update public.app_config set min_version_ios = '9' $$,
  '42501', null, 'anon cannot change config'
);
reset role;

-- Carol: a stranger who follows alice one way --------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000c","role":"authenticated"}';

select results_eq(
  $$ select id from public.checkins order by id $$,
  $$ values ('10000000-0000-0000-0000-000000000001'::uuid), ('10000000-0000-0000-0000-000000000005'::uuid) $$,
  'a one-way follower sees only public check-ins, and none of a private profile or inside a delay'
);
select is(
  (select count(*)::int from public.comments where body = 'on private'), 0,
  'comments on hidden check-ins are hidden'
);
select is(
  (select count(*)::int from public.salutes s where s.checkin_id = '10000000-0000-0000-0000-000000000001'), 1,
  'salutes on visible check-ins are readable'
);
select is(
  (select home_airport from public.get_profile('00000000-0000-0000-0000-00000000000a')), 1,
  'home airport of a public profile is visible'
);
select is(
  (select home_airport from public.get_profile('00000000-0000-0000-0000-00000000000d')), null::integer,
  'home airport of a private profile is hidden from strangers'
);
select is(
  (select post_delay_minutes from public.get_profile('00000000-0000-0000-0000-00000000000f')), null::integer,
  'another user''s post delay is hidden'
);
select throws_ok($$ select home_airport from public.profiles $$, '42501', null, 'home_airport cannot be read directly');
select throws_ok($$ select location from public.checkins $$, '42501', null, 'users cannot read raw GPS');
select is((select count(*)::int from public.entitlements), 0, 'other users'' entitlements are hidden');
select is((select count(*)::int from public.blocks), 0, 'other users'' blocks are hidden');
select is(
  (select count(*)::int from public.follows where follower = '00000000-0000-0000-0000-00000000000d'), 0,
  'connections of a private profile are hidden'
);

select throws_ok(
  $$ insert into public.salutes (user_id, checkin_id) values ('00000000-0000-0000-0000-00000000000c', '10000000-0000-0000-0000-000000000003') $$,
  '42501', null, 'cannot salute a check-in you cannot see'
);
select throws_ok(
  $$ insert into public.salutes (user_id, checkin_id) values ('00000000-0000-0000-0000-00000000000b', '10000000-0000-0000-0000-000000000001') $$,
  '42501', null, 'cannot salute as someone else'
);
select lives_ok(
  $$ insert into public.salutes (user_id, checkin_id) values ('00000000-0000-0000-0000-00000000000c', '10000000-0000-0000-0000-000000000001') $$,
  'can salute a visible check-in as yourself'
);
select throws_ok(
  $$ insert into public.comments (checkin_id, user_id, body) values ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000b', 'fake') $$,
  '42501', null, 'cannot comment as someone else'
);
select lives_ok(
  $$ insert into public.comments (checkin_id, user_id, body) values ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000c', 'hello') $$,
  'can comment on a visible check-in'
);
select throws_ok(
  $$ insert into public.comments (id, checkin_id, user_id, body, created_at) values (gen_random_uuid(), '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000c', 'x', now()) $$,
  '42501', null, 'cannot choose a comment''s id or timestamp'
);

select throws_ok(
  $$ insert into public.follows (follower, followee) values ('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000c') $$,
  '42501', null, 'cannot create a follow for someone else'
);
select throws_ok(
  $$ insert into public.spotting_locations (airport_id, name, created_by, status) values (1, 'Mine', '00000000-0000-0000-0000-00000000000c', 'approved') $$,
  '42501', null, 'cannot self-approve a spotting location'
);
select throws_ok(
  $$ insert into public.spotting_locations (airport_id, name, created_by) values (1, 'Fake', '00000000-0000-0000-0000-00000000000a') $$,
  '42501', null, 'cannot submit a spotting location as someone else'
);
select lives_ok(
  $$ insert into public.spotting_locations (airport_id, name, created_by) values (1, 'Mine', '00000000-0000-0000-0000-00000000000c') $$,
  'can submit a spotting location'
);
select is(
  (select status from public.spotting_locations where name = 'Mine'), 'pending',
  'a submitted spotting location waits for moderation and is visible to its author'
);
select is(
  (select count(*)::int from public.spotting_locations where name = 'Pending'), 0,
  'other people''s pending spotting locations are hidden'
);

-- Writes reserved for Edge Functions
select throws_ok(
  $$ insert into public.checkins (id, user_id, kind, occurred_at) values (gen_random_uuid(), '00000000-0000-0000-0000-00000000000c', 'spotted', now()) $$,
  '42501', null, 'check-ins cannot be written directly'
);
select throws_ok($$ delete from public.checkins $$, '42501', null, 'check-ins cannot be deleted directly');
select throws_ok(
  $$ insert into public.user_badges (user_id, badge_id) values ('00000000-0000-0000-0000-00000000000c', 'x') $$,
  '42501', null, 'badges cannot be awarded directly'
);
select throws_ok(
  $$ insert into public.entitlements (user_id, entitlement, store, product_id, original_transaction_id, status) values ('00000000-0000-0000-0000-00000000000c', 'pro', 'promo', 'free', 'x', 'active') $$,
  '42501', null, 'users cannot grant themselves Pro'
);
select throws_ok($$ insert into public.reports (target_type, target_id) values ('user', 'x') $$, '42501', null, 'reports cannot be written directly');
select throws_ok($$ select * from public.store_events $$, '42501', null, 'store events cannot be read');
select throws_ok(
  $$ insert into public.devices (id, user_id, platform, app_version) values (gen_random_uuid(), '00000000-0000-0000-0000-00000000000c', 'ios', '1') $$,
  '42501', null, 'devices cannot be inserted directly'
);

-- Own profile
select throws_ok(
  $$ update public.profiles set xp = 999999 where id = '00000000-0000-0000-0000-00000000000c' $$,
  '42501', null, 'users cannot change their own XP'
);
select lives_ok(
  $$ update public.profiles set username = 'carol' where id = '00000000-0000-0000-0000-00000000000c' $$,
  'users can change their own username'
);
select throws_ok(
  $$ update public.profiles set username = 'Not Valid!' where id = '00000000-0000-0000-0000-00000000000c' $$,
  '23514', null, 'usernames must match the allowed format'
);
select is_empty(
  $$ update public.profiles set display_name = 'hacked' where id = '00000000-0000-0000-0000-00000000000a' returning id $$,
  'users cannot change other profiles'
);
select is_empty(
  $$ update public.notification_prefs set salutes = false where user_id = '00000000-0000-0000-0000-00000000000a' returning user_id $$,
  'users cannot change other users'' notification settings'
);
reset role;

-- Bob: a friend of alice, dave and frank -------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000b","role":"authenticated"}';

select results_eq(
  $$ select id from public.checkins order by id $$,
  $$ values ('10000000-0000-0000-0000-000000000001'::uuid), ('10000000-0000-0000-0000-000000000002'::uuid),
            ('10000000-0000-0000-0000-000000000004'::uuid), ('10000000-0000-0000-0000-000000000005'::uuid),
            ('10000000-0000-0000-0000-000000000006'::uuid) $$,
  'a friend sees friends-only posts, private profiles and delayed posts, but not private posts'
);
select is(
  (select home_airport from public.get_profile('00000000-0000-0000-0000-00000000000d')), 1,
  'a friend sees the home airport of a private profile'
);

-- Devices
select lives_ok(
  $$ select public.register_device('20000000-0000-0000-0000-000000000001', 'ios', '1.0', 'token-1', 'production') $$,
  'can register a device'
);
select is((select count(*)::int from public.devices), 1, 'can read own device');
select lives_ok(
  $$ select public.register_device('20000000-0000-0000-0000-000000000001', 'ios', '1.1', 'token-1', 'production') $$,
  'registering again updates the device'
);
select is(
  (select app_version from public.devices where id = '20000000-0000-0000-0000-000000000001'), '1.1',
  'registering again stores the new version'
);
select throws_ok(
  $$ update public.devices set push_token = 'x' $$,
  '42501', null, 'devices cannot be updated directly'
);
reset role;

-- Carol signs in on bob's phone: same token, new device ID.
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000c","role":"authenticated"}';
select is((select count(*)::int from public.devices), 0, 'other users'' devices are hidden');
select is_empty(
  $$ delete from public.devices where id = '20000000-0000-0000-0000-000000000001' returning id $$,
  'cannot delete another user''s device'
);
select lives_ok(
  $$ select public.register_device('20000000-0000-0000-0000-000000000002', 'ios', '1.1', 'token-1', 'production') $$,
  'a phone can change accounts'
);
reset role;
select is(
  (select user_id from public.devices where push_token = 'token-1'),
  '00000000-0000-0000-0000-00000000000c'::uuid,
  'a push token belongs only to the latest account on that phone'
);
select is((select count(*)::int from public.devices where id = '20000000-0000-0000-0000-000000000001'), 0, 'the previous account''s device row is removed');

-- Eve: blocked by alice ------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000e","role":"authenticated"}';

select is(
  (select count(*)::int from public.checkins where user_id = '00000000-0000-0000-0000-00000000000a'), 0,
  'a blocked user cannot see the blocker''s check-ins'
);
select is(
  (select count(*)::int from public.profiles where id = '00000000-0000-0000-0000-00000000000a'), 0,
  'a blocked user cannot see the blocker''s profile'
);
select is(
  (select count(*)::int from public.get_profile('00000000-0000-0000-0000-00000000000a')), 0,
  'get_profile returns nothing for a blocked user'
);
select is((select count(*)::int from public.blocks), 0, 'a blocked user cannot see the block');
select throws_ok(
  $$ insert into public.follows (follower, followee) values ('00000000-0000-0000-0000-00000000000e', '00000000-0000-0000-0000-00000000000a') $$,
  '42501', null, 'a blocked user cannot follow the blocker'
);
select throws_ok(
  $$ insert into public.salutes (user_id, checkin_id) values ('00000000-0000-0000-0000-00000000000e', '10000000-0000-0000-0000-000000000002') $$,
  '42501', null, 'a blocked user cannot salute the blocker''s check-ins'
);
reset role;

-- Alice: owner, and the one who blocked eve ------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000a","role":"authenticated"}';

select is(
  (select count(*)::int from public.checkins where user_id = '00000000-0000-0000-0000-00000000000a'), 3,
  'owners see all their own check-ins'
);
select is((select count(*)::int from public.blocks), 1, 'users see their own blocks');
select is(
  (select count(*)::int from public.profiles where id = '00000000-0000-0000-0000-00000000000e'), 0,
  'a blocker does not see the blocked profile'
);
select is(
  (select count(*)::int from public.comments where body = 'from eve'), 0,
  'comments by a blocked user are hidden'
);
select is(
  (select count(*)::int from public.salutes where user_id = '00000000-0000-0000-0000-00000000000e'), 0,
  'salutes by a blocked user are hidden'
);
select is((select count(*)::int from public.entitlements), 1, 'users see their own entitlements');
select is((select status from public.entitlements), 'active', 'users can read their entitlement status');
select throws_ok(
  $$ select original_transaction_id from public.entitlements $$,
  '42501', null, 'store transaction IDs are not exposed'
);
select is(
  (select post_delay_minutes from public.get_profile('00000000-0000-0000-0000-00000000000a')), 0,
  'users can read their own post delay'
);
select lives_ok(
  $$ update public.notification_prefs set salutes = false where user_id = '00000000-0000-0000-0000-00000000000a' $$,
  'users can change their own notification settings'
);
select isnt_empty(
  $$ delete from public.comments where body = 'from bob' returning id $$,
  'owners can delete comments on their check-ins'
);
reset role;

-- Service role keeps access for Edge Functions and webhooks --------------------------------
set local role service_role;
select lives_ok(
  $$ insert into public.store_events (id, store, payload) values (gen_random_uuid(), 'app_store', '{}') $$,
  'the service role can write store events'
);
select lives_ok(
  $$ update public.entitlements set status = 'expired' where user_id = '00000000-0000-0000-0000-00000000000a' $$,
  'the service role can update entitlements'
);
select ok(
  (select location is not null from public.checkins where id = '10000000-0000-0000-0000-000000000001'),
  'the service role can read raw GPS'
);
reset role;

-- Account deletion removes everything the user owns -----------------------------------------
delete from auth.users where id = '00000000-0000-0000-0000-00000000000a';
select is(
  (select count(*)::int from public.checkins where user_id = '00000000-0000-0000-0000-00000000000a'), 0,
  'deleting an account removes its check-ins'
);
select is(
  (select count(*)::int from public.entitlements where user_id = '00000000-0000-0000-0000-00000000000a'), 0,
  'deleting an account removes its entitlements'
);
select is(
  (select count(*)::int from public.follows where '00000000-0000-0000-0000-00000000000a' in (follower, followee)), 0,
  'deleting an account removes its connections'
);

select * from finish();
rollback;
