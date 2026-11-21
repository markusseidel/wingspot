-- Activity inbox: every event is stored, only some are pushed, and the person reads their own list.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

-- 1 = the person with the inbox and a phone, 2 and 3 act, 4 has no phone and switched salutes off, 5 gets blocked
insert into auth.users (id, aud, role, email)
select ('00000000-0000-0000-0000-0000000008' || lpad(n::text, 2, '0'))::uuid, 'authenticated', 'authenticated', 'inbox' || n || '@example.test'
from generate_series(1, 5) n;
create function pg_temp.u(n integer) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000008' || lpad(n::text, 2, '0'))::uuid;
$$;
create function pg_temp.as_user(n integer) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(n), 'role', 'authenticated')::text, true),
         set_config('role', 'authenticated', true);
$$;
create function pg_temp.reset_role() returns void language sql as $$
  select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
$$;
insert into public.devices (id, user_id, platform, push_token, push_env, app_version, locale)
values ('88000000-0000-0000-0000-000000000001', pg_temp.u(1), 'ios', 'inbox-token', 'production', '0.2.0', 'en_US');
update public.notification_prefs set salutes = false where user_id = pg_temp.u(4);

-- People without a phone, or with a kind switched off, still get the event, but silent and already "sent".
insert into public.follows (follower, followee) values (pg_temp.u(2), pg_temp.u(1)), (pg_temp.u(2), pg_temp.u(4));
select is((select count(*)::int from public.notifications where recipient = pg_temp.u(1) and kind = 'follow' and not silent and sent_at is null), 1,
  'a follow with a phone is pushed');
select is((select count(*)::int from public.notifications where recipient = pg_temp.u(4) and kind = 'follow' and silent and sent_at is not null), 1,
  'a follow without a phone is stored silently');
select is((select count(*)::int from public.claim_notifications(10) where actor_id = pg_temp.u(2)), 1, 'only the pushed one reaches the sender');

-- Check-ins to talk about
insert into public.airports (id, icao, iata, name, country_code, continent, location) values
  (897001, 'ZZZP', 'ZZP', 'Inbox A', 'DE', 'EU', 'POINT(8 50)'), (897002, 'ZZZQ', 'ZZQ', 'Inbox B', 'DE', 'EU', 'POINT(9 51)');
insert into public.checkins (id, user_id, kind, occurred_at, origin_id, destination_id, visibility) values
  ('a8000000-0000-7000-8000-000000000001', pg_temp.u(1), 'flown', '2026-03-01T10:00:00Z', 897001, 897002, 'public');
insert into public.follows (follower, followee) values (pg_temp.u(1), pg_temp.u(2));

insert into public.salutes (checkin_id, user_id) values ('a8000000-0000-7000-8000-000000000001', pg_temp.u(2));
insert into public.comments (checkin_id, user_id, body) values ('a8000000-0000-7000-8000-000000000001', pg_temp.u(3), 'Nice one');

update public.notifications set created_at = now() - interval '3 minutes' where recipient = pg_temp.u(1) and kind = 'follow';
update public.notifications set created_at = now() - interval '2 minutes' where recipient = pg_temp.u(1) and kind = 'salute';
update public.notifications set created_at = now() - interval '1 minute' where recipient = pg_temp.u(1) and kind = 'comment';
select pg_temp.as_user(1);
select is((select count(*)::int from public.get_notifications()), 3, 'the inbox lists follow, salute and comment');
select is((select kind from public.get_notifications() limit 1), 'comment', 'newest first');
select is((select subject from public.get_notifications() where kind = 'salute'), 'ZZP → ZZQ', 'a row about a flight names the route');
select is((select snippet from public.get_notifications() where kind = 'comment'), 'Nice one', 'a comment keeps its start');
select is((select username from public.get_notifications() where kind = 'follow'), (select username from public.profiles where id = pg_temp.u(2)), 'and who did it');
select is(public.unread_notification_count(), 3, 'all three are unread');

-- Paging
select is((select count(*)::int from public.get_notifications(null, 2)), 2, 'a page has at most the asked number');
select is((select count(*)::int from public.get_notifications((select max(created_at) from public.get_notifications()), 30)), 2,
  'before returns only older rows');

-- Opening one row marks only that row, and only for its owner
select pg_temp.reset_role();
select set_config('test.salute_note', (select id::text from public.notifications where recipient = pg_temp.u(1) and kind = 'salute'), true);
select pg_temp.as_user(3);
select public.mark_notification_read(current_setting('test.salute_note')::uuid);
select pg_temp.reset_role();
select is((select count(*)::int from public.notifications where recipient = pg_temp.u(1) and kind = 'salute' and read_at is null), 1,
  'someone else cannot mark my row read');
select pg_temp.as_user(1);
select public.mark_notification_read((select id from public.get_notifications() where kind = 'salute'));
select is(public.unread_notification_count(), 2, 'one row read, two left');
select is((select is_read from public.get_notifications() where kind = 'salute'), true, 'it is that row');
select is((select count(*)::int from public.get_notifications() where not is_read), 2, 'the others stay unread');

select public.mark_notifications_read();
select is(public.unread_notification_count(), 0, 'reading marks everything');
select is((select count(*)::int from public.get_notifications() where not is_read), 0, 'and the list agrees');
select pg_temp.reset_role();
insert into public.salutes (checkin_id, user_id) values ('a8000000-0000-7000-8000-000000000001', pg_temp.u(3));
select pg_temp.as_user(1);
select is(public.unread_notification_count(), 1, 'a new event is unread again');

-- Other people's rows are never visible
select pg_temp.as_user(5);
select is((select count(*)::int from public.get_notifications()), 0, 'someone else sees their own list, not this one');
select is(public.unread_notification_count(), 0, 'and counts their own');
select pg_temp.reset_role();

-- Blocking hides the person's rows
insert into public.blocks (blocker, blocked) values (pg_temp.u(1), pg_temp.u(3));
select pg_temp.as_user(1);
select is((select count(*)::int from public.get_notifications() where actor_id = pg_temp.u(3)), 0, 'a blocked person leaves the inbox');
select pg_temp.reset_role();
delete from public.blocks;

-- A check-in the person may not see any more is not linked
update public.checkins set visibility = 'private' where id = 'a8000000-0000-7000-8000-000000000001';
insert into public.notifications (recipient, kind, actor, checkin_id) values
  (pg_temp.u(5), 'salute', pg_temp.u(3), 'a8000000-0000-7000-8000-000000000001');
select pg_temp.as_user(5);
select is((select count(*)::int from public.get_notifications()), 0, 'a row about a check-in you may not see is left out');
select pg_temp.reset_role();

-- Not callable without signing in
select set_config('role', 'anon', true);
select throws_ok($$ select * from public.get_notifications() $$, '42501', null, 'anonymous visitors cannot read an inbox');
select pg_temp.reset_role();

select * from finish();
rollback;
