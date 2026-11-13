-- Android push: a person with only an Android device is notified, and the claim carries each device's platform.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

insert into auth.users (id, aud, role, email)
select ('00000000-0000-0000-0000-0000000009' || lpad(n::text, 2, '0'))::uuid, 'authenticated', 'authenticated', 'android' || n || '@example.test'
from generate_series(1, 2) n;
create function pg_temp.u(n integer) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000009' || lpad(n::text, 2, '0'))::uuid;
$$;

insert into public.devices (id, user_id, platform, push_token, push_env, app_version, locale) values
  ('99000000-0000-0000-0000-000000000001', pg_temp.u(1), 'android', 'fcm-token-1', 'production', '0.1.0', 'de');

select private.queue_notification(pg_temp.u(1), 'follow', pg_temp.u(2), null, null);
select is((select count(*)::int from public.notifications where recipient = pg_temp.u(1)), 1, 'an Android device is enough to be notified');

select is(
  (select (devices -> 0 ->> 'platform') from public.claim_notifications(10) where actor_id = pg_temp.u(2) limit 1),
  'android', 'the claim says which platform each device is on');

select * from finish();
rollback;
