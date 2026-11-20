-- Deleting a check-in takes back what it earned: levels, progress, unlock date and XP follow what is left,
-- while every other evaluation still keeps a level. Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

insert into auth.users (id, aud, role, email) values
  ('00000000-0000-0000-0000-000000000e01', 'authenticated', 'authenticated', 'badgedelete@example.test');
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000e01', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);

select is(public.sync_checkins('[{"id":"e0000000-0000-7000-8000-000000000001","kind":"spotted","occurred_at":"2026-05-01T10:00:00Z","registration":"D-DELAA"}]'::jsonb) #>> '{badges_unlocked,0,id}',
  'wheels_up', 'the first check-in unlocks Wheels Up');
select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
select ok((select xp from public.profiles where id = '00000000-0000-0000-0000-000000000e01') > 0, 'and gives XP');
select is((select level from public.user_badges where user_id = '00000000-0000-0000-0000-000000000e01' and badge_id = 'wheels_up'), 1, 'at level 1');

-- Deleting it takes the badge and the XP back
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000e01', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);
select public.delete_checkin('e0000000-0000-7000-8000-000000000001');
select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
select is((select level from public.user_badges where user_id = '00000000-0000-0000-0000-000000000e01' and badge_id = 'wheels_up'), null, 'the badge is gone');
select is((select unlocked_at from public.user_badges where user_id = '00000000-0000-0000-0000-000000000e01' and badge_id = 'wheels_up'), null, 'with its unlock date');
select is((select xp from public.profiles where id = '00000000-0000-0000-0000-000000000e01'), 0, 'and the XP is back to 0');

-- Earning it again is a new unlock
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000e01', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);
select is(public.sync_checkins('[{"id":"e0000000-0000-7000-8000-000000000002","kind":"spotted","occurred_at":"2026-05-02T10:00:00Z","registration":"D-DELAB"}]'::jsonb) #>> '{badges_unlocked,0,id}',
  'wheels_up', 'a new check-in unlocks it again');

-- A leveled badge only drops as far as the check-ins left allow, and only when one is deleted
select public.sync_checkins(
  (select jsonb_agg(jsonb_build_object('id', format('e0000000-0000-7000-8000-%s', lpad((100 + n)::text, 12, '0')), 'kind', 'spotted',
                                       'occurred_at', '2026-06-01T10:00:00Z'::timestamptz + n * interval '1 minute', 'registration', 'D-ABC' || chr(64 + n)))
   from generate_series(1, 10) n));
select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
select is((select level from public.user_badges where user_id = '00000000-0000-0000-0000-000000000e01' and badge_id = 'logbook'), 1, 'eleven check-ins give Logbook level 1 (10)');
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000e01', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);
select public.delete_checkin('e0000000-0000-7000-8000-000000000101');
select public.delete_checkin('e0000000-0000-7000-8000-000000000102');
select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
select is((select level from public.user_badges where user_id = '00000000-0000-0000-0000-000000000e01' and badge_id = 'logbook'), null, 'nine check-ins are below the first Logbook level');
select is((select progress from public.user_badges where user_id = '00000000-0000-0000-0000-000000000e01' and badge_id = 'logbook'), 9, 'and progress follows');

-- Another evaluation keeps what is there
update public.user_badges set level = 1 where user_id = '00000000-0000-0000-0000-000000000e01' and badge_id = 'logbook';
select private.evaluate_badges('00000000-0000-0000-0000-000000000e01');
select is((select level from public.user_badges where user_id = '00000000-0000-0000-0000-000000000e01' and badge_id = 'logbook'), 1, 'an upload or the badges page never lowers a level');

select * from finish();
rollback;
