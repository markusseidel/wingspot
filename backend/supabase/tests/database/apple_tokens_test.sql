-- Sign in with Apple refresh tokens are out of reach for the client roles.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

insert into auth.users (id, aud, role, email) values
  ('00000000-0000-0000-0000-000000000701', 'authenticated', 'authenticated', 'apple1@example.test');
insert into public.apple_tokens (user_id, refresh_token) values ('00000000-0000-0000-0000-000000000701', 'secret');

select ok(
  (select relrowsecurity from pg_class where oid = 'public.apple_tokens'::regclass), 'row level security is on');
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000701', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);
select throws_ok($$ select * from public.apple_tokens $$, '42501', null, 'a signed-in user cannot read the tokens, not even their own');
select throws_ok($$ insert into public.apple_tokens (user_id, refresh_token) values ('00000000-0000-0000-0000-000000000701', 'x') $$,
                 '42501', null, 'or write them');
select set_config('role', 'anon', true), set_config('request.jwt.claims', '', true);
select throws_ok($$ select * from public.apple_tokens $$, '42501', null, 'neither can an anonymous visitor');
select set_config('role', 'postgres', true);
delete from auth.users where id = '00000000-0000-0000-0000-000000000701';
select is((select count(*)::int from public.apple_tokens), 0, 'deleting the user removes the token');

select * from finish();
rollback;
