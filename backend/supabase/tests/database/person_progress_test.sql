-- A person's level and earned badges on their profile page: who may see them, and what is left out.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

-- Badge definitions of the real hidden badges are not in the repository (see backend/private/README.md), so the test makes
-- its own hidden one. The ones a database may already have are removed for the length of the test.
delete from public.user_badges where badge_id in (select id from public.badges where hidden);
delete from public.badges where hidden;
insert into public.badges (id, name, description, category, kind, rule, levels, hidden, valid_from, position) values
  ('test_hidden_secret', '{"en": "Test secret"}'::jsonb, '{"en": "Test"}'::jsonb, 'hidden', 'single', '{"metric": "checkins_total"}'::jsonb, '{1}', true, null, 43);

-- a = the person looked at, b = a friend of a, c = follows a only, d = stranger, e = blocked by a, f = a private profile
insert into auth.users (id, aud, role, email)
select format('00000000-0000-0000-0000-0000000000%s', n)::uuid, 'authenticated', 'authenticated', format('prog%s@example.test', n)
from unnest(array['a1','a2','a3','a4','a5','a6']) n;
insert into public.follows (follower, followee) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a2'), ('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000a1'),
  ('00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-0000000000a1');
insert into public.blocks (blocker, blocked) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a5');
update public.profiles set is_private = true where id = '00000000-0000-0000-0000-0000000000a6';

-- a has a level and two earned badges (one of them hidden) and one that is not earned yet; f has one too
update public.profiles set xp = 400 where id in ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a6');
insert into public.user_badges (user_id, badge_id, level, progress, unlocked_at)
select u, b, l, 1, now()
from (values ('00000000-0000-0000-0000-0000000000a1'::uuid), ('00000000-0000-0000-0000-0000000000a6'::uuid)) users(u),
     (values ('wheels_up', 1), ('test_hidden_secret', 1), ('logbook', 0)) earned(b, l);

select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000a2', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);
select is((public.get_person_progress('00000000-0000-0000-0000-0000000000a1') ->> 'xp')::int, 400, 'a friend sees the xp');
select is((public.get_person_progress('00000000-0000-0000-0000-0000000000a1') ->> 'level')::int, 3, 'and the level');
select is((select string_agg(e ->> 'id', ',') from jsonb_array_elements(public.get_person_progress('00000000-0000-0000-0000-0000000000a1') -> 'badges') e),
  'wheels_up', 'only the earned badge that is not hidden is listed: no hidden one, no unearned one');
select is((public.get_person_progress('00000000-0000-0000-0000-0000000000a1') ->> 'hidden_remaining')::int, 0, 'nothing is said about hidden badges');
select is(public.get_person_progress('00000000-0000-0000-0000-0000000000a6') is null, true, 'a private profile stays closed to a non-friend');

-- a follows b back, so b is a friend of a, and b may see a. a follower only (c) sees a public profile too, not a private one.
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000a3', 'role', 'authenticated')::text, true);
select is((public.get_person_progress('00000000-0000-0000-0000-0000000000a1') ->> 'level')::int, 3, 'anyone signed in sees a public profile');
select is(public.get_person_progress('00000000-0000-0000-0000-0000000000a6') is null, true, 'a follower is not a friend, so a private profile stays closed');

select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000a5', 'role', 'authenticated')::text, true);
select is(public.get_person_progress('00000000-0000-0000-0000-0000000000a1') is null, true, 'someone who is blocked sees nothing');

select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000a1', 'role', 'authenticated')::text, true);
select is((public.get_person_progress('00000000-0000-0000-0000-0000000000a1') ->> 'level')::int, 3, 'you can read your own');

select set_config('role', 'anon', true), set_config('request.jwt.claims', '', true);
select throws_ok($$ select public.get_person_progress('00000000-0000-0000-0000-0000000000a1') $$, '42501', null, 'signed-out clients cannot call it');

select * from finish();
rollback;
