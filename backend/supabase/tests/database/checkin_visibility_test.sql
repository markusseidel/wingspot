-- Setting who sees one check-in: only your own, with a mark that "apply to existing" respects.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

insert into auth.users (id, aud, role, email) values
  ('00000000-0000-0000-0000-000000000f01', 'authenticated', 'authenticated', 'vis1@example.test'),
  ('00000000-0000-0000-0000-000000000f02', 'authenticated', 'authenticated', 'vis2@example.test');
insert into public.checkins (id, user_id, kind, occurred_at, visibility) values
  ('f0000000-0000-7000-8000-00000000000a', '00000000-0000-0000-0000-000000000f01', 'spotted', '2026-01-01T10:00:00Z', 'friends'),
  ('f0000000-0000-7000-8000-00000000000b', '00000000-0000-0000-0000-000000000f01', 'spotted', '2026-01-02T10:00:00Z', 'friends'),
  ('f0000000-0000-7000-8000-00000000000c', '00000000-0000-0000-0000-000000000f02', 'spotted', '2026-01-03T10:00:00Z', 'private');
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000f01', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);

select is((select visibility from public.get_checkin_visibility('f0000000-0000-7000-8000-00000000000a')), 'friends', 'you can read the visibility of your own check-in');
select is((select is_custom from public.get_checkin_visibility('f0000000-0000-7000-8000-00000000000a')), false, 'it follows the account at first');
select is((select count(*)::int from public.get_checkin_visibility('f0000000-0000-7000-8000-00000000000c')), 0, 'nothing for someone else''s check-in');

select is(public.set_checkin_visibility('f0000000-0000-7000-8000-00000000000a', 'followers'), 'followers', 'one check-in is set to followers');
select is((select is_custom from public.get_checkin_visibility('f0000000-0000-7000-8000-00000000000a')), true, 'and is marked as set by hand');
select is(public.set_checkin_visibility('f0000000-0000-7000-8000-00000000000c', 'public'), null, 'someone else''s check-in is left alone');
select throws_ok($$ select public.set_checkin_visibility('f0000000-0000-7000-8000-00000000000a', 'everyone') $$, '22023', 'invalid_visibility', 'an unknown level is refused');

select is(public.set_sharing('public', true), 1, 'apply to existing changes only the check-in that follows the account');
select is((select visibility from public.get_checkin_visibility('f0000000-0000-7000-8000-00000000000a')), 'followers', 'the one set by hand kept its level');
select is((select visibility from public.get_checkin_visibility('f0000000-0000-7000-8000-00000000000b')), 'public', 'the other one changed');

select is(public.set_checkin_visibility('f0000000-0000-7000-8000-00000000000a', null), 'public', 'going back to the account setting gives its level');
select is((select is_custom from public.get_checkin_visibility('f0000000-0000-7000-8000-00000000000a')), false, 'and follows it again');

select * from finish();
rollback;
