-- Milestone 8c: private profile and post delay, set by the account itself.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

-- author 1 (public check-ins), friend 2, stranger 3
insert into auth.users (id, aud, role, email)
select ('00000000-0000-0000-0000-0000000008' || lpad(n::text, 2, '0'))::uuid, 'authenticated', 'authenticated',
       'privacy' || n || '@example.test'
from generate_series(1, 3) n;

create function pg_temp.as_user(n integer) returns void language sql as $$
  select set_config('request.jwt.claims',
           json_build_object('sub', '00000000-0000-0000-0000-0000000008' || lpad(n::text, 2, '0'), 'role', 'authenticated')::text, true),
         set_config('role', 'authenticated', true);
$$;
create function pg_temp.u(n integer) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000008' || lpad(n::text, 2, '0'))::uuid;
$$;

insert into public.follows (follower, followee) values (pg_temp.u(1), pg_temp.u(2)), (pg_temp.u(2), pg_temp.u(1));
insert into public.checkins (id, user_id, kind, occurred_at, visibility) values
  ('81000000-0000-0000-0000-000000000001', pg_temp.u(1), 'spotted', now() - interval '10 minutes', 'public'),
  ('81000000-0000-0000-0000-000000000002', pg_temp.u(1), 'spotted', now() - interval '3 hours',    'public');

-- The account sets its own values
select pg_temp.as_user(1);
select lives_ok($$ update public.profiles set post_delay_minutes = 60 where id = pg_temp.u(1) $$, 'an account can set its post delay');
select is((select post_delay_minutes from public.get_profile(pg_temp.u(1))), 60, 'and read it back');
select throws_ok($$ update public.profiles set post_delay_minutes = 1441 where id = pg_temp.u(1) $$, '23514', null, 'more than a day is refused');
select throws_ok($$ update public.profiles set post_delay_minutes = -5 where id = pg_temp.u(1) $$, '23514', null, 'and so is a negative delay');
update public.profiles set post_delay_minutes = 1 where id = pg_temp.u(3);
select is((select post_delay_minutes from public.get_profile(pg_temp.u(3))), null::integer, 'but not another account''s delay, which stays hidden');

-- What the delay does
select is((select count(*)::int from public.checkins where id = '81000000-0000-0000-0000-000000000001'), 1, 'the owner sees a fresh check-in');
select pg_temp.as_user(2);
select is((select count(*)::int from public.checkins where id = '81000000-0000-0000-0000-000000000001'), 1, 'a friend sees it at once');
select pg_temp.as_user(3);
select is((select count(*)::int from public.checkins where id = '81000000-0000-0000-0000-000000000001'), 0, 'a stranger doesn''t, within the delay');
select is((select count(*)::int from public.checkins where id = '81000000-0000-0000-0000-000000000002'), 1, 'but sees an older check-in');

-- A private profile
select pg_temp.as_user(1);
update public.profiles set is_private = true where id = pg_temp.u(1);
select pg_temp.as_user(3);
select is((select count(*)::int from public.checkins where id = '81000000-0000-0000-0000-000000000002'), 0, 'a private profile hides its public check-ins from strangers');
select pg_temp.as_user(2);
select is((select count(*)::int from public.checkins where id = '81000000-0000-0000-0000-000000000002'), 1, 'but not from friends');

select * from finish();
rollback;
