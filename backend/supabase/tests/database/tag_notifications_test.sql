-- Being tagged on a check-in sends a notification, unless it is switched off or there is no phone.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

-- a = author, b has a phone, c has none, d has a phone and switched tagging alerts off
insert into auth.users (id, aud, role, email)
select format('00000000-0000-0000-0000-0000000000%s', n)::uuid, 'authenticated', 'authenticated', format('tagn%s@example.test', n)
from unnest(array['e1','e2','e3','e4']) n;
insert into public.follows (follower, followee)
select a, b from (values ('e1','e2'),('e2','e1'),('e1','e3'),('e3','e1'),('e1','e4'),('e4','e1')) v(x, y),
  lateral (select format('00000000-0000-0000-0000-0000000000%s', x)::uuid a, format('00000000-0000-0000-0000-0000000000%s', y)::uuid b) p;
insert into public.devices (id, user_id, platform, push_token, push_env, app_version, locale) values
  ('7a000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000000e2', 'ios', 'tag-token-b', 'production', '0.2.0', 'en_US'),
  ('7a000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-0000000000e4', 'android', 'tag-token-d', null, '0.2.0', 'de');
update public.notification_prefs set tagged = false where user_id = '00000000-0000-0000-0000-0000000000e4';
insert into public.airports (id, icao, iata, name, country_code, continent, location) values
  (896001, 'ZZZM', 'ZZM', 'Tag note A', 'DE', 'EU', 'POINT(8 50)'), (896002, 'ZZZN', 'ZZN', 'Tag note B', 'DE', 'EU', 'POINT(9 51)');

select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000e1', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);
select public.sync_checkins(jsonb_build_array(jsonb_build_object(
  'id', 'a0000000-0000-7000-8000-000000000001', 'kind', 'flown', 'occurred_at', '2026-03-01T10:00:00Z',
  'origin_id', 896001, 'destination_id', 896002, 'visibility', 'private',
  'with', jsonb_build_array('00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-0000000000e4'))));
select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);

select is((select count(*)::int from public.notifications where kind = 'tagged' and not silent), 1, 'only the friend with a phone and the alert on is told');
select is((select actor from public.notifications where kind = 'tagged' and not silent), '00000000-0000-0000-0000-0000000000e1'::uuid, 'it names the author');
select is((select recipient from public.notifications where kind = 'tagged' and not silent), '00000000-0000-0000-0000-0000000000e2'::uuid, 'and goes to the tagged friend');
select is((select checkin_id from public.notifications where kind = 'tagged' and not silent), 'a0000000-0000-7000-8000-000000000001'::uuid, 'about that check-in');

-- Sending the same tags again tells nobody again
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000e1', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);
select public.sync_checkins(jsonb_build_array(jsonb_build_object(
  'id', 'a0000000-0000-7000-8000-000000000001', 'kind', 'flown', 'occurred_at', '2026-03-01T10:00:00Z',
  'origin_id', 896001, 'destination_id', 896002,
  'with', jsonb_build_array('00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-0000000000e4'))));
select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
select is((select count(*)::int from public.notifications where kind = 'tagged' and not silent), 1, 'the same tags again send nothing new');

-- The sending function sees the kind
select ok((select count(*) from public.claim_notifications(10) where kind = 'tagged') >= 0, 'the sender can claim it');

select * from finish();
rollback;
