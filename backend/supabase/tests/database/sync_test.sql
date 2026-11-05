-- sync_checkins: who may call it, ownership of ids, and what it creates.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

insert into auth.users (id, aud, role, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated', 'sync-a@example.test'),
  ('00000000-0000-0000-0000-0000000000b1', 'authenticated', 'authenticated', 'sync-b@example.test');

create function pg_temp.as_user(uid text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true),
         set_config('role', 'authenticated', true);
$$;

-- Not callable without signing in --------------------------------------------------------
set local role anon;
select throws_ok(
  $$select public.sync_checkins('[]'::jsonb)$$,
  '42501', null, 'anonymous visitors cannot call sync_checkins'
);
reset role;

-- Alice uploads --------------------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');

select is(
  public.sync_checkins('[{"id":"20000000-0000-0000-0000-000000000001","kind":"spotted","occurred_at":"2026-01-01T10:00:00Z","registration":"D-SYNC"}]'::jsonb) -> 'results',
  '[{"id":"20000000-0000-0000-0000-000000000001","status":"stored"}]'::jsonb,
  'a valid check-in is stored'
);
select is(
  public.sync_checkins('[{"id":"20000000-0000-0000-0000-000000000001","kind":"spotted","occurred_at":"2026-01-01T10:00:00Z","registration":"D-SYNC"}]'::jsonb) -> 'results' -> 0 ->> 'status',
  'stored', 'uploading it again is stored again'
);
select throws_ok($$select public.sync_checkins('{}'::jsonb)$$, '22023', null, 'items must be an array');
select throws_ok(
  $$select public.sync_checkins((select jsonb_agg(jsonb_build_object('id', gen_random_uuid())) from generate_series(1, 51)))$$,
  '22023', null, 'more than 50 items are refused'
);

-- Bob can't take Alice's id ----------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000000b1');
select is(
  public.sync_checkins('[{"id":"20000000-0000-0000-0000-000000000001","kind":"spotted","occurred_at":"2026-01-01T10:00:00Z","registration":"D-SYNC"}]'::jsonb) -> 'results' -> 0 ->> 'code',
  'id_taken', 'another user''s id is rejected'
);

-- Checked as the owner ---------------------------------------------------------------------
reset role;
select is((select user_id from public.checkins where id = '20000000-0000-0000-0000-000000000001'),
          '00000000-0000-0000-0000-0000000000a1'::uuid, 'the check-in still belongs to alice');
select is((select visibility from public.checkins where id = '20000000-0000-0000-0000-000000000001'),
          'private', 'check-ins are private by default');
select is((select count(*)::int from public.aircraft where registration = 'D-SYNC'), 1, 'the aircraft was created once');
select is((select data_status from public.aircraft where registration = 'D-SYNC'), 'user_submitted', 'a new aircraft is user submitted');

select * from finish();
rollback;
