-- Milestone 7a: sharing choice, feed, counts, reports and the comment word filter.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

-- viewer 1, public author 2, friend 3, private profile 4, blocked 5, stranger 6
insert into auth.users (id, aud, role, email)
select ('00000000-0000-0000-0000-0000000005' || lpad(n::text, 2, '0'))::uuid, 'authenticated', 'authenticated',
       'social' || n || '@example.test'
from generate_series(1, 6) n;

create function pg_temp.as_user(n integer) returns void language sql as $$
  select set_config('request.jwt.claims',
           json_build_object('sub', '00000000-0000-0000-0000-0000000005' || lpad(n::text, 2, '0'), 'role', 'authenticated')::text, true),
         set_config('role', 'authenticated', true);
$$;
create function pg_temp.as_owner() returns void language sql as $$
  select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
$$;
create function pg_temp.u(n integer) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000005' || lpad(n::text, 2, '0'))::uuid;
$$;

update public.profiles set is_private = true where id = pg_temp.u(4);
insert into public.airports (id, icao, iata, name, country_code, continent, location)
  values (71, 'EDDF', 'FRA', 'Frankfurt', 'DE', 'EU', 'POINT(8.57 50.03)');
insert into public.aircraft_types (icao_code, manufacturer, model) values ('A320', 'Airbus', 'A320');
insert into public.aircraft (id, registration, type_icao, is_sensitive) values
  (901, 'D-AIZZ', 'A320', false), (902, 'D-SECR', 'A320', true);

-- 1 follows 2, 3 (mutual), 4 (one way), 5 (then blocks 5), and not 6. 3 follows 1 back.
insert into public.follows (follower, followee) values
  (pg_temp.u(1), pg_temp.u(2)), (pg_temp.u(1), pg_temp.u(3)), (pg_temp.u(3), pg_temp.u(1)),
  (pg_temp.u(1), pg_temp.u(4)), (pg_temp.u(1), pg_temp.u(5));

-- 1 blocks 5, which also removes that follow.
insert into public.blocks (blocker, blocked) values (pg_temp.u(1), pg_temp.u(5));

insert into public.checkins (id, user_id, kind, occurred_at, visibility, aircraft_id, airport_id) values
  ('50000000-0000-0000-0000-000000000001', pg_temp.u(1), 'spotted', now() - interval '1 hour',  'private', 901, 71),
  ('50000000-0000-0000-0000-000000000002', pg_temp.u(2), 'spotted', now() - interval '2 hours', 'public',  901, 71),
  ('50000000-0000-0000-0000-000000000003', pg_temp.u(2), 'spotted', now() - interval '3 hours', 'private', 901, 71),
  ('50000000-0000-0000-0000-000000000004', pg_temp.u(3), 'spotted', now() - interval '4 hours', 'friends', 902, 71),
  ('50000000-0000-0000-0000-000000000005', pg_temp.u(4), 'spotted', now() - interval '5 hours', 'public',  901, 71),
  ('50000000-0000-0000-0000-000000000006', pg_temp.u(5), 'spotted', now() - interval '6 hours', 'public',  901, 71),
  ('50000000-0000-0000-0000-000000000007', pg_temp.u(6), 'spotted', now() - interval '7 hours', 'public',  901, 71);

-- Sharing choice ------------------------------------------------------------------------------
select pg_temp.as_user(6);
select is((select default_visibility from public.get_profile(pg_temp.u(6))), 'private', 'new accounts share nothing');
select is((select default_visibility from public.get_profile(pg_temp.u(2))), null, 'the sharing choice is only returned to its owner');
select is(public.sync_checkins('[{"id":"60000000-0000-0000-0000-000000000001","kind":"spotted","occurred_at":"2026-01-01T10:00:00Z","registration":"D-AAAA"}]'::jsonb) -> 'results' -> 0 ->> 'status', 'stored', 'a check-in is stored');
select is((select c.visibility from public.checkins c where c.id = '60000000-0000-0000-0000-000000000001'), 'private', 'without a choice it is private');
select is(public.set_sharing('friends'), 0, 'setting the choice alone changes no earlier check-in');
select is(public.sync_checkins('[{"id":"60000000-0000-0000-0000-000000000002","kind":"spotted","occurred_at":"2026-01-01T10:00:00Z","registration":"D-AAAB"}]'::jsonb) -> 'results' -> 0 ->> 'status', 'stored', 'another check-in is stored');
select is((select c.visibility from public.checkins c where c.id = '60000000-0000-0000-0000-000000000002'), 'friends', 'a new check-in follows the choice');
select is((select c.visibility from public.checkins c where c.id = '60000000-0000-0000-0000-000000000001'), 'private', 'the earlier one is untouched');
select is(public.sync_checkins('[{"id":"60000000-0000-0000-0000-000000000003","kind":"spotted","occurred_at":"2026-01-01T10:00:00Z","registration":"D-AAAC","visibility":"public"}]'::jsonb) -> 'results' -> 0 ->> 'status', 'stored', 'a check-in with its own visibility is stored');
select is((select c.visibility from public.checkins c where c.id = '60000000-0000-0000-0000-000000000003'), 'public', 'its own visibility wins');
select is(public.set_sharing('public', true), 2, 'applying to earlier check-ins counts the ones that changed');
select is((select count(*)::int from public.checkins c where c.user_id = pg_temp.u(6) and c.visibility = 'public' and c.id::text like '60000000%'), 3, 'all three are public now');
select throws_ok($$ select public.set_sharing('everyone') $$, '22023', 'invalid_visibility', 'an unknown choice is refused');
select is((select default_visibility from public.get_profile(pg_temp.u(6))), 'public', 'the owner reads the new choice');

-- Feed ----------------------------------------------------------------------------------------
select pg_temp.as_user(1);
select results_eq(
  $$ select id::text from public.get_feed() order by occurred_at desc, id desc $$,
  $$ values ('50000000-0000-0000-0000-000000000001'), ('50000000-0000-0000-0000-000000000002'), ('50000000-0000-0000-0000-000000000004') $$,
  'the feed has own check-ins and what followed people let this viewer see'
);
select is((select count(*)::int from public.get_feed() where user_id = pg_temp.u(6)), 0, 'people not followed are not in the feed');
select is((select count(*)::int from public.get_feed() where user_id = pg_temp.u(5)), 0, 'a blocked person is not in the feed');
select is((select count(*)::int from public.get_feed() where user_id = pg_temp.u(4)), 0, 'a private profile that does not follow back stays out');
select is((select count(*)::int from public.get_feed() where id = '50000000-0000-0000-0000-000000000003'), 0, 'private check-ins of others stay out');
select is((select registration from public.get_feed() where id = '50000000-0000-0000-0000-000000000004'), null, 'the registration of a sensitive aircraft is hidden from others');
select is((select registration from public.get_feed() where id = '50000000-0000-0000-0000-000000000002'), 'D-AIZZ', 'an ordinary registration shows');
select is((select airport_code from public.get_feed() where id = '50000000-0000-0000-0000-000000000002'), 'FRA', 'the airport code shows');
select is((select type_name from public.get_feed() where id = '50000000-0000-0000-0000-000000000002'), 'Airbus A320', 'the type name shows');

-- Paging: one at a time, no repeats, no gaps
select is((select id::text from public.get_feed(page_size => 1)), '50000000-0000-0000-0000-000000000001', 'page one');
select is((select id::text from public.get_feed((select occurred_at from public.checkins where id = '50000000-0000-0000-0000-000000000001'),
                                                 '50000000-0000-0000-0000-000000000001', 1)), '50000000-0000-0000-0000-000000000002', 'page two');
select is((select count(*)::int from public.get_feed(null, null, 500)), 3, 'the page size is capped, not an error');

-- Counts follow the same rules ----------------------------------------------------------------
select pg_temp.as_owner();
insert into public.salutes (user_id, checkin_id) values
  (pg_temp.u(1), '50000000-0000-0000-0000-000000000002'), (pg_temp.u(6), '50000000-0000-0000-0000-000000000002'),
  (pg_temp.u(3), '50000000-0000-0000-0000-000000000002');
insert into public.comments (checkin_id, user_id, body) values
  ('50000000-0000-0000-0000-000000000002', pg_temp.u(6), 'hello'),
  ('50000000-0000-0000-0000-000000000002', pg_temp.u(3), 'hi');
select pg_temp.as_user(1);
select is((select salutes from public.get_feed() where id = '50000000-0000-0000-0000-000000000002'), 3, 'salutes are counted');
select is((select comments from public.get_feed() where id = '50000000-0000-0000-0000-000000000002'), 2, 'comments are counted');
select is((select saluted from public.get_feed() where id = '50000000-0000-0000-0000-000000000002'), true, 'the viewer sees their own salute');
select pg_temp.as_owner();
insert into public.blocks (blocker, blocked) values (pg_temp.u(1), pg_temp.u(6));
select pg_temp.as_user(1);
select is((select salutes from public.get_feed() where id = '50000000-0000-0000-0000-000000000002'), 2, 'a blocked person''s salute is not counted');
select is((select comments from public.get_feed() where id = '50000000-0000-0000-0000-000000000002'), 1, 'a blocked person''s comment is not counted');
select pg_temp.as_user(2);
select is((select saluted from public.get_feed() where id = '50000000-0000-0000-0000-000000000002'), false, 'someone who did not salute sees false');

-- Reports -------------------------------------------------------------------------------------
select pg_temp.as_user(1);
select is(public.report('checkin', '50000000-0000-0000-0000-000000000002', 'spam'), 'reported', 'a visible check-in can be reported');
select is(public.report('checkin', '50000000-0000-0000-0000-000000000003', null), 'unknown_target', 'a check-in the reporter cannot see cannot be reported');
select is(public.report('user', pg_temp.u(1)::text, null), 'unknown_target', 'a person cannot report themselves');
select is(public.report('user', pg_temp.u(6)::text, null), 'unknown_target', 'a blocked person cannot be reported through the app');
select is(public.report('user', pg_temp.u(2)::text, 'rude'), 'reported', 'a user can be reported');
select is(public.report('banana', pg_temp.u(2)::text, null), 'invalid_kind', 'an unknown kind is refused');
select is(public.report('user', 'not-a-uuid', null), 'unknown_target', 'a target that is not an id is unknown');
select is(public.report('comment', (select c.id::text from public.comments c where c.body = 'hi'), null), 'reported', 'a visible comment can be reported');
select is(public.report('user', pg_temp.u(2)::text, 'again'), 'reported', 'reporting again is accepted');
select pg_temp.as_owner();
select is((select count(*)::int from public.reports where reporter = pg_temp.u(1) and target_type = 'user'), 1, 'but it does not add a second open report');
select is((select count(*)::int from public.reports where reporter = pg_temp.u(1)), 3, 'three reports were stored');
select is((select reason from public.reports where target_type = 'user' and reporter = pg_temp.u(1)), 'rude', 'the first reason is kept');
select pg_temp.as_user(1);
select throws_ok($$ select * from public.reports $$, '42501', null, 'signed-in users cannot read reports');
select pg_temp.as_owner();
insert into public.reports (reporter, target_type, target_id)
  select pg_temp.u(1), 'user', gen_random_uuid()::text from generate_series(1, 20);
select pg_temp.as_user(1);
select is(public.report('user', pg_temp.u(3)::text, null), 'too_many', 'after 20 reports in an hour more are refused');

-- Blocked list --------------------------------------------------------------------------------
select pg_temp.as_user(1);
select results_eq(
  $$ select id::text from public.get_blocks() order by id $$,
  $$ values (pg_temp.u(5)::text), (pg_temp.u(6)::text) $$,
  'the caller sees the people they blocked, though their profiles are hidden'
);
select is((select count(*)::int from public.profiles where id = pg_temp.u(5)), 0, 'a blocked person''s profile is hidden');
select pg_temp.as_user(5);
select is((select count(*)::int from public.get_blocks()), 0, 'the blocked person does not see who blocked them');

-- Word filter ---------------------------------------------------------------------------------
select pg_temp.as_user(3);
select throws_ok(
  $$ insert into public.comments (checkin_id, user_id, body)
     values ('50000000-0000-0000-0000-000000000002', pg_temp.u(3), 'What a SCHEISSE photo!') $$,
  '23514', 'comment_not_allowed', 'a comment with a blocked word is refused, in any case'
);
select lives_ok(
  $$ insert into public.comments (checkin_id, user_id, body)
     values ('50000000-0000-0000-0000-000000000002', pg_temp.u(3), 'Nice shot, great class of aircraft') $$,
  'a normal comment passes, even with a blocked word hidden inside another word ("class")'
);
select lives_ok(
  $$ insert into public.comments (checkin_id, user_id, body)
     values ('50000000-0000-0000-0000-000000000002', pg_temp.u(3), 'Shitake mushrooms') $$,
  'a word that only starts with a blocked word passes'
);
select throws_ok($$ select * from private.blocked_words $$, '42501', null, 'the word list is not readable by users');

select * from finish();
rollback;
