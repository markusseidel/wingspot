-- Milestone 12c: alerts for the check-ins of people you follow.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

-- 1 is the author. 2 is a friend of 1. 3 only follows 1. 4 follows nobody.
insert into auth.users (id, aud, role, email)
select ('00000000-0000-0000-0000-0000000008' || lpad(n::text, 2, '0'))::uuid, 'authenticated', 'alert' || n || '@example.test'
from generate_series(1, 4) n;
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
create function pg_temp.alerts(n integer) returns integer language sql as $$
  select count(*)::integer from public.notifications where recipient = pg_temp.u(n) and kind = 'checkin'
$$;
-- A check-in by the author, made now unless said otherwise.
create function pg_temp.checkin(kind_ public.checkin_kind, visibility_ text default 'public',
                                when_ timestamptz default now(), context_ text default null, aircraft_ integer default 881)
returns uuid language sql as $$
  insert into public.checkins (id, user_id, kind, occurred_at, visibility, aircraft_id, airport_id, visit_context, origin_id, destination_id)
  values (gen_random_uuid(), pg_temp.u(1), kind_, when_, visibility_,
          case when kind_ = 'spotted' then aircraft_ end,
          case when kind_ = 'airport' then 881001 end, context_,
          case when kind_ = 'flown' then 881001 end, case when kind_ = 'flown' then 881002 end)
  returning id;
$$;

update public.profiles set is_private = false where id = pg_temp.u(1);
insert into public.devices (id, user_id, platform, push_token, push_env, app_version, locale) values
  ('88000000-0000-0000-0000-000000000002', pg_temp.u(2), 'ios', 'alert-token-2', 'production', '0.2.0', 'en_US'),
  ('88000000-0000-0000-0000-000000000003', pg_temp.u(3), 'ios', 'alert-token-3', 'production', '0.2.0', 'en_US');
insert into public.aircraft_types (icao_code, manufacturer, model) values ('A321', 'Airbus', 'A321');
insert into public.aircraft (id, registration, type_icao, is_sensitive) values
  (881, 'D-AIAL', 'A321', false), (882, 'D-AISE', 'A321', true);
insert into public.airports (id, icao, iata, name, country_code, continent, location) values
  (881001, 'ZZZA', 'ZZA', 'Alert test A', 'DE', 'EU', 'POINT(8 50)'),
  (881002, 'ZZZB', 'ZZB', 'Alert test B', 'DE', 'EU', 'POINT(9 51)');
insert into public.follows (follower, followee) values
  (pg_temp.u(2), pg_temp.u(1)), (pg_temp.u(1), pg_temp.u(2)), (pg_temp.u(3), pg_temp.u(1));

-- The rules: who may set one, who can read them
select pg_temp.as_user(2);
select lives_ok($$ insert into public.notification_rules (watcher, target, spotted, flown) values (pg_temp.u(2), pg_temp.u(1), true, true) $$,
                'you can set an alert for someone you follow');
select pg_temp.as_user(4);
select throws_ok($$ insert into public.notification_rules (watcher, target, spotted) values (pg_temp.u(4), pg_temp.u(1), true) $$,
                 '42501', null, 'but not for someone you do not follow');
select pg_temp.as_user(3);
insert into public.notification_rules (watcher, target, spotted) values (pg_temp.u(3), pg_temp.u(1), true);
select is((select count(*)::int from public.notification_rules), 1, 'you read only your own rules');
select pg_temp.reset_role();

-- Spotted, flown, airport
select pg_temp.checkin('spotted');
select is(pg_temp.alerts(2), 1, 'a friend with the spotted switch on is told');
select is(pg_temp.alerts(3), 1, 'so is a follower of a public profile');
select is(pg_temp.alerts(4), 0, 'and someone with no rule is not');
select pg_temp.checkin('flown');
select is(pg_temp.alerts(2), 2, 'the flown switch tells the friend about a flight');
select is(pg_temp.alerts(3), 1, 'but not the follower who only switched on spotted');
select pg_temp.checkin('airport', 'public', now(), 'spotting');
select is(pg_temp.alerts(2), 2, 'an airport visit tells nobody while that switch is off');
update public.notification_rules set airport = true where watcher = pg_temp.u(2);
select pg_temp.checkin('airport', 'public', now(), 'spotting');
select is(pg_temp.alerts(2), 3, 'and does once it is on');
select pg_temp.checkin('airport', 'public', now(), 'departing');
select pg_temp.checkin('airport', 'public', now(), 'arriving');
select is(pg_temp.alerts(2), 3, 'the airport visits a flight creates are not announced, the flight is');

-- What stays quiet
select pg_temp.checkin('spotted', 'public', now() - interval '3 days');
select is(pg_temp.alerts(2), 3, 'a check-in from days ago, added later, tells nobody');
select pg_temp.checkin('spotted', 'private');
select is(pg_temp.alerts(2), 3, 'a private check-in tells nobody');
select pg_temp.checkin('spotted', 'friends');
select is(pg_temp.alerts(2), 4, 'a friends-only check-in tells a friend');
select is(pg_temp.alerts(3), 1, 'but not a follower who is no friend');
update public.profiles set post_delay_minutes = 60 where id = pg_temp.u(1);
select pg_temp.checkin('spotted');
select is(pg_temp.alerts(3), 1, 'a delayed public check-in is not visible to a follower yet, so it tells nobody');
select is(pg_temp.alerts(2), 5, 'a friend sees it at once');
update public.profiles set post_delay_minutes = 0 where id = pg_temp.u(1);

-- Sensitive aircraft: others never get the registration
create temp table sensitive_checkin as select pg_temp.checkin('spotted', 'public', now(), null, 882) as id;
select is((select subject from public.claim_notifications(100) c, sensitive_checkin s
           where c.checkin_id = s.id and c.checkin_kind = 'spotted' limit 1),
          'A321', 'a sensitive aircraft shows its type to others, not its registration');

-- Switching off, and unfollowing
update public.notification_prefs set followed_checkins = false where user_id = pg_temp.u(2);
select pg_temp.checkin('spotted');
select is(pg_temp.alerts(2), 6, 'the master switch stops all of them, the count stays');
select pg_temp.as_user(3);
delete from public.follows where follower = pg_temp.u(3);
select pg_temp.reset_role();
select is((select count(*)::int from public.notification_rules where watcher = pg_temp.u(3)), 0, 'unfollowing ends the alerts');

select * from finish();
rollback;
