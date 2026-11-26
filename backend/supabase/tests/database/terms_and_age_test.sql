-- Minimum age 16 (docs/MINIMUM-AGE-PLAN.md): accept_terms, get_my_terms, privacy of the fields, the export.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

insert into auth.users (id, aud, role, email)
select format('00000000-0000-0000-0000-0000000000%s', n)::uuid, 'authenticated', 'authenticated', format('terms%s@example.test', n)
from unnest(array['a1','a2']) n;

create function pg_temp.as_user(u text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', ('00000000-0000-0000-0000-0000000000' || u)::uuid, 'role', 'authenticated')::text, true),
         set_config('role', 'authenticated', true);
$$;
create function pg_temp.reset_role() returns void language sql as $$
  select set_config('role', 'postgres', true), set_config('request.jwt.claims', '', true);
$$;

-- A new account has agreed to nothing
select pg_temp.as_user('a1');
select results_eq('select terms_version, age_confirmed_at from public.get_my_terms()', $$values (0, null::timestamptz)$$, 'a new account has version 0 and no age confirmation');

-- Version 1 (the rules without the age point) does not record an age confirmation
select is(public.accept_terms(1), 1, 'version 1 is stored');
select is((select age_confirmed_at from public.get_my_terms()), null, 'version 1 records no age confirmation');

-- Version 2 records it
select is(public.accept_terms(2), 2, 'version 2 is stored');
select isnt((select age_confirmed_at from public.get_my_terms()), null, 'version 2 records the age confirmation');

-- The version only goes up, and the first confirmation is kept
select pg_temp.reset_role();
update public.profiles set age_confirmed_at = '2026-01-01T00:00:00Z' where id = '00000000-0000-0000-0000-0000000000a1';
select pg_temp.as_user('a1');
select is(public.accept_terms(1), 2, 'a lower version does not overwrite a higher one');
select is(public.accept_terms(3), 3, 'a higher version replaces it');
select is((select age_confirmed_at from public.get_my_terms()), '2026-01-01T00:00:00Z'::timestamptz, 'the first age confirmation is kept');

-- Only the caller's row changes
select pg_temp.as_user('a2');
select results_eq('select terms_version, age_confirmed_at from public.get_my_terms()', $$values (0, null::timestamptz)$$, 'another account is untouched');

-- Nonsense versions are refused
select throws_ok('select public.accept_terms(0)', '22023', 'invalid version', 'version 0 is refused');
select throws_ok('select public.accept_terms(null)', '22023', 'invalid version', 'no version is refused');

-- Other people cannot read the fields
select throws_ok($$select terms_version from public.profiles where id = '00000000-0000-0000-0000-0000000000a1'$$, '42501', null, 'others cannot read the rules version');
select throws_ok($$select age_confirmed_at from public.profiles where id = '00000000-0000-0000-0000-0000000000a1'$$, '42501', null, 'others cannot read the age confirmation');

-- The export carries both
select pg_temp.as_user('a1');
select is((public.export_my_data() -> 'profile' ->> 'terms_version')::int, 3, 'the export carries the rules version');
select isnt(public.export_my_data() -> 'profile' ->> 'age_confirmed_at', null, 'the export carries the age confirmation');

-- Nobody signed in
select pg_temp.reset_role();
select set_config('role', 'anon', true);
select throws_ok('select public.accept_terms(2)', '42501', null, 'anon cannot accept');
select throws_ok('select * from public.get_my_terms()', '42501', null, 'anon cannot read');

select * from finish();
rollback;
