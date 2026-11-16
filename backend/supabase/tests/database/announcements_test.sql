-- Announcements: everyone reads the active, unexpired ones through get_announcements(); nobody writes or reads the table.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

insert into auth.users (id, aud, role, email) values
  ('00000000-0000-0000-0000-000000000e01', 'authenticated', 'authenticated', 'ann1@example.test');
insert into public.announcements (id, title_en, body_en, title_de, body_de, created_at, expires_at, active) values
  ('e0000000-0000-4000-8000-00000000000a', 'Live', 'Live body', 'Live de', 'Live Text', now() - interval '2 days', null, true),
  ('e0000000-0000-4000-8000-00000000000b', 'Newer', 'Newer body', null, null, now() - interval '1 day', now() + interval '1 day', true),
  ('e0000000-0000-4000-8000-00000000000c', 'Expired', 'Expired body', null, null, now() - interval '3 days', now() - interval '1 hour', true),
  ('e0000000-0000-4000-8000-00000000000d', 'Off', 'Off body', null, null, now() - interval '1 day', null, false);

select throws_ok($$ insert into public.announcements (title_en, body_en, title_de) values ('a', 'b', 'only a title') $$, '23514', null, 'a German title needs a German body');

set local role anon;
set local request.jwt.claims = '{"role":"anon"}';
select is((select string_agg(title_en, ',' order by created_at desc) from public.get_announcements()), 'Newer,Live', 'signed-out users see active, unexpired announcements, newest first');
select is((select title_de from public.get_announcements() where title_en = 'Live'), 'Live de', 'with the German text when there is one');
select is((select title_de from public.get_announcements() where title_en = 'Newer'), null, 'and nothing when there is none');
select throws_ok($$ select * from public.announcements $$, '42501', null, 'anon cannot read the table');
select throws_ok($$ insert into public.announcements (title_en, body_en) values ('x', 'y') $$, '42501', null, 'anon cannot write');

select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000e01', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);
select is((select count(*)::int from public.get_announcements()), 2, 'signed-in users see the same');
select throws_ok($$ select * from public.announcements $$, '42501', null, 'authenticated cannot read the table');
select throws_ok($$ insert into public.announcements (title_en, body_en) values ('x', 'y') $$, '42501', null, 'authenticated cannot write');
select throws_ok($$ update public.announcements set active = false $$, '42501', null, 'authenticated cannot change them');
select throws_ok($$ delete from public.announcements $$, '42501', null, 'authenticated cannot delete them');

select * from finish();
rollback;
