-- Release notes: everyone reads the active notes of one platform through get_release_notes(); nobody writes or reads the table.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

insert into auth.users (id, aud, role, email) values
  ('00000000-0000-0000-0000-000000000f01', 'authenticated', 'authenticated', 'rn1@example.test');
insert into public.release_notes (platform, version, build, kind, title_en, body_en, title_de, body_de) values
  ('ios', '0.2.0', 2026112307, 'beta', 'Seven', '- one', 'Sieben', '- eins'),
  ('ios', '0.2.0', 2026112308, 'beta', 'Eight', '- two', null, null),
  ('android', '0.2.0', 2026112301, 'beta', 'Droid', '- three', null, null);
insert into public.release_notes (platform, version, build, title_en, body_en, active) values
  ('ios', '0.2.0', 2026112309, 'Hidden', '- off', false);

select throws_ok($$ insert into public.release_notes (platform, version, build, title_en, body_en) values ('ios', '0.2.0', 2026112307, 'dup', 'x') $$, '23505', null, 'a build has one note per platform');
select throws_ok($$ insert into public.release_notes (platform, version, build, title_en, body_en) values ('web', '0.2.0', 1, 'x', 'y') $$, '23514', null, 'only ios and android');
select throws_ok($$ insert into public.release_notes (platform, version, build, title_en, body_en, title_de) values ('ios', '0.2.0', 5, 'a', 'b', 'only a title') $$, '23514', null, 'a German title needs a German body');

set local role anon;
set local request.jwt.claims = '{"role":"anon"}';
select is((select string_agg(title_en, ',' order by build desc) from public.get_release_notes('ios')), 'Eight,Seven', 'signed-out users see the active notes of the platform, newest build first');
select is((select title_de from public.get_release_notes('ios') where title_en = 'Seven'), 'Sieben', 'with the German text when there is one');
select is((select title_de from public.get_release_notes('ios') where title_en = 'Eight'), null, 'and nothing when there is none');
select is((select count(*)::int from public.get_release_notes('android')), 1, 'the other platform is separate');
select is((select count(*)::int from public.get_release_notes('web')), 0, 'an unknown platform has none');
select is((select count(*)::int from public.get_release_notes('ios', 1)), 1, 'the limit applies');
select throws_ok($$ select * from public.release_notes $$, '42501', null, 'anon cannot read the table');
select throws_ok($$ insert into public.release_notes (platform, version, build, title_en, body_en) values ('ios', '1', 1, 'x', 'y') $$, '42501', null, 'anon cannot write');

select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000f01', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);
select is((select count(*)::int from public.get_release_notes('ios')), 2, 'signed-in users see the same');
select throws_ok($$ select * from public.release_notes $$, '42501', null, 'authenticated cannot read the table');
select throws_ok($$ insert into public.release_notes (platform, version, build, title_en, body_en) values ('ios', '1', 1, 'x', 'y') $$, '42501', null, 'authenticated cannot write');
select throws_ok($$ update public.release_notes set active = false $$, '42501', null, 'authenticated cannot change them');
select throws_ok($$ delete from public.release_notes $$, '42501', null, 'authenticated cannot delete them');

select * from finish();
rollback;
