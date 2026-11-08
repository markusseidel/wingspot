-- Milestone 10b: who gets a notification, and the functions the send-push function uses.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

-- 1 author with a phone, 2 and 3 actors, 4 has no phone, 5 is blocked by the author
insert into auth.users (id, aud, role, email)
select ('00000000-0000-0000-0000-0000000007' || lpad(n::text, 2, '0'))::uuid, 'authenticated', 'authenticated', 'push' || n || '@example.test'
from generate_series(1, 5) n;
create function pg_temp.u(n integer) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000007' || lpad(n::text, 2, '0'))::uuid;
$$;
create function pg_temp.as_user(n integer) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true),
         set_config('role', 'authenticated', true);
$$;
create function pg_temp.reset_role() returns void language sql as $$
  select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
$$;
create function pg_temp.pending() returns integer language sql as $$
  select count(*)::integer from public.notifications
$$;

insert into public.devices (id, user_id, platform, push_token, push_env, app_version, locale) values
  ('77000000-0000-0000-0000-000000000001', pg_temp.u(1), 'ios', 'token-1a', 'production', '0.2.0', 'de_DE'),
  ('77000000-0000-0000-0000-000000000002', pg_temp.u(1), 'ios', 'token-1b', 'sandbox', '0.2.0', 'en_US'),
  ('77000000-0000-0000-0000-000000000003', pg_temp.u(1), 'android', 'token-android', null, '0.2.0', 'en'),
  ('77000000-0000-0000-0000-000000000004', pg_temp.u(3), 'ios', 'token-3', 'production', '0.2.0', 'en_US'),
  ('77000000-0000-0000-0000-000000000005', pg_temp.u(5), 'ios', 'token-5', 'production', '0.2.0', 'en_US');
insert into public.aircraft_types (icao_code, manufacturer, model) values ('A320', 'Airbus', 'A320');
insert into public.aircraft (id, registration, type_icao) values (771, 'D-AIPC', 'A320');
insert into public.checkins (id, user_id, kind, occurred_at, visibility, aircraft_id) values
  ('77100000-0000-0000-0000-000000000001', pg_temp.u(1), 'spotted', now() - interval '3 hours', 'public', 771),
  ('77100000-0000-0000-0000-000000000002', pg_temp.u(2), 'spotted', now() - interval '3 hours', 'public', 771);
insert into public.blocks (blocker, blocked) values (pg_temp.u(1), pg_temp.u(5));

-- Follows
select pg_temp.as_user(2);
insert into public.follows (follower, followee) values (pg_temp.u(2), pg_temp.u(1));
select pg_temp.reset_role();
select is((select count(*)::int from public.notifications where recipient = pg_temp.u(1) and kind = 'follow' and actor = pg_temp.u(2)), 1,
          'a follow tells the person who was followed');
select pg_temp.as_user(2);
delete from public.follows where follower = pg_temp.u(2);
insert into public.follows (follower, followee) values (pg_temp.u(2), pg_temp.u(1));
select pg_temp.reset_role();
select is((select count(*)::int from public.notifications where recipient = pg_temp.u(1) and kind = 'follow'), 1,
          'following again within the hour does not tell them again');

insert into public.follows (follower, followee) values (pg_temp.u(2), pg_temp.u(4));
select is((select count(*)::int from public.notifications where recipient = pg_temp.u(4)), 0, 'nothing for someone without a phone');

-- Salutes
select pg_temp.as_user(2);
insert into public.salutes (user_id, checkin_id) values (pg_temp.u(2), '77100000-0000-0000-0000-000000000001');
select pg_temp.reset_role();
select is((select count(*)::int from public.notifications where recipient = pg_temp.u(1) and kind = 'salute'), 1, 'a salute tells the owner of the check-in');
select pg_temp.as_user(1);
insert into public.salutes (user_id, checkin_id) values (pg_temp.u(1), '77100000-0000-0000-0000-000000000001');
select pg_temp.reset_role();
select is((select count(*)::int from public.notifications where actor = pg_temp.u(1)), 0, 'saluting your own check-in tells nobody');

-- Comments
select pg_temp.as_user(2);
insert into public.comments (checkin_id, user_id, body) values ('77100000-0000-0000-0000-000000000001', pg_temp.u(2), repeat('x', 200));
select pg_temp.reset_role();
select is((select length(snippet) from public.notifications where kind = 'comment'), 80, 'a comment tells the owner, with the first 80 characters');
select pg_temp.as_user(2);
insert into public.comments (checkin_id, user_id, body) values ('77100000-0000-0000-0000-000000000001', pg_temp.u(2), 'second');
select pg_temp.reset_role();
select is((select count(*)::int from public.notifications where kind = 'comment'), 2, 'every comment counts, also from the same person');

-- Blocked people, and switched-off kinds
select pg_temp.as_user(5);
select throws_ok($$ insert into public.salutes (user_id, checkin_id) values ('00000000-0000-0000-0000-000000000705', '77100000-0000-0000-0000-000000000001') $$,
                 null, null, 'someone blocked by the author cannot even salute');
select pg_temp.reset_role();
-- (queue_notification is the one place that decides; check the block rule directly)
select private.queue_notification(pg_temp.u(1), 'salute', pg_temp.u(5), '77100000-0000-0000-0000-000000000001', null);
select is((select count(*)::int from public.notifications where actor = pg_temp.u(5)), 0, 'nothing from or to a blocked pair');

update public.notification_prefs set salutes = false where user_id = pg_temp.u(1);
select private.queue_notification(pg_temp.u(1), 'salute', pg_temp.u(3), '77100000-0000-0000-0000-000000000001', null);
select is((select count(*)::int from public.notifications where actor = pg_temp.u(3)), 0, 'nothing for a kind the person switched off');
select private.queue_notification(pg_temp.u(1), 'comment', pg_temp.u(3), '77100000-0000-0000-0000-000000000001', 'still on');
select is((select count(*)::int from public.notifications where actor = pg_temp.u(3)), 1, 'other kinds still arrive');

-- The daily cap
insert into public.notifications (recipient, kind, actor, checkin_id, snippet, sent_at)
select pg_temp.u(3), 'comment', pg_temp.u(2), null, 'filler', now() from generate_series(1, 30);
select private.queue_notification(pg_temp.u(3), 'follow', pg_temp.u(1), null, null);
select is((select count(*)::int from public.notifications where recipient = pg_temp.u(3) and kind = 'follow'), 0, 'at most 30 a day per person');

-- Claiming
delete from public.notifications where recipient = pg_temp.u(3);
select is((select count(*)::int from public.claim_notifications(10)), 5, 'claim takes the five waiting rows');
select is((select count(*)::int from public.claim_notifications(10)), 0, 'and nobody else can take them for five minutes');
select is((select jsonb_array_length(devices) from public.claim_notifications(10)), null, 'nothing left to claim');
update public.notifications set claimed_at = null;
select is((select jsonb_array_length(devices) from public.claim_notifications(1)), 2, 'a row carries the iPhones of its recipient, but not the Android phone');
update public.notifications set claimed_at = null;
select is((select subject from public.claim_notifications(10) where kind = 'salute'), 'D-AIPC', 'a salute says what it was about');
update public.notifications set claimed_at = null;
select is((select attempts from public.notifications where kind = 'follow'), 3, 'each claim counts as an attempt');

-- Finishing
select public.finish_notification((select id from public.notifications where kind = 'follow'), true, array['77000000-0000-0000-0000-000000000002']::uuid[]);
select is((select count(*)::int from public.notifications where kind = 'follow' and sent_at is not null), 1, 'a delivered row is marked sent');
select is((select count(*)::int from public.devices where id = '77000000-0000-0000-0000-000000000002'), 0, 'a dead device is removed');
update public.notifications set claimed_at = now() where kind = 'comment';
select public.finish_notification((select id from public.notifications where kind = 'comment' limit 1), false);
select is((select count(*)::int from public.notifications where kind = 'comment' and claimed_at is null and sent_at is null), 1, 'a row that failed goes back for another try');

-- Expiry
update public.notifications set sent_at = null, claimed_at = null, created_at = now() - interval '2 days' where kind = 'salute';
select is((select count(*)::int from public.claim_notifications(10) where kind = 'salute'), 0, 'rows older than a day are not sent');
update public.notifications set sent_at = null, claimed_at = null, attempts = 5 where kind = 'comment';
select is((select count(*)::int from public.claim_notifications(10) where kind = 'comment'), 0, 'rows tried five times are given up');

-- Who may call what
select pg_temp.as_user(1);
select throws_ok($$ select * from public.claim_notifications(10) $$, '42501', null, 'signed-in users cannot claim');
select throws_ok($$ select public.finish_notification(gen_random_uuid(), true) $$, '42501', null, 'or finish');
select throws_ok($$ select * from public.notifications $$, '42501', null, 'and cannot read the outbox');
select set_config('role', 'anon', true), set_config('request.jwt.claims', '', true);
select throws_ok($$ select * from public.claim_notifications(10) $$, '42501', null, 'anonymous visitors cannot claim');
select set_config('role', 'service_role', true);
select lives_ok($$ select * from public.claim_notifications(1) $$, 'the service role can');

-- Deleting a person removes their notifications
select pg_temp.reset_role();
delete from auth.users where id = pg_temp.u(2);
select is((select count(*)::int from public.notifications where actor = pg_temp.u(2)), 0, 'deleting an account removes what it caused');

select * from finish();
rollback;
