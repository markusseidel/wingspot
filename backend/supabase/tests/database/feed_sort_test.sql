-- The feed sorted by the day of the event or by when it was checked in, with paging on either.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

insert into auth.users (id, aud, role, email) values
  ('00000000-0000-0000-0000-000000000c01', 'authenticated', 'authenticated', 'feedsort@example.test');
insert into public.aircraft_types (icao_code, manufacturer, model) values ('A321', 'Airbus', 'A321');
-- Three check-ins: a is the oldest event but was added last, c is the newest event but was added first.
insert into public.checkins (id, user_id, kind, occurred_at, created_at, visibility, type_icao) values
  ('c0000000-0000-7000-8000-00000000000a', '00000000-0000-0000-0000-000000000c01', 'spotted', '2026-01-01T10:00:00Z', '2026-11-03T10:00:00Z', 'private', 'A321'),
  ('c0000000-0000-7000-8000-00000000000b', '00000000-0000-0000-0000-000000000c01', 'spotted', '2026-02-01T10:00:00Z', '2026-11-02T10:00:00Z', 'private', 'A321'),
  ('c0000000-0000-7000-8000-00000000000c', '00000000-0000-0000-0000-000000000c01', 'spotted', '2026-03-01T10:00:00Z', '2026-11-01T10:00:00Z', 'private', 'A321');
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000c01', 'role', 'authenticated')::text, true),
       set_config('role', 'authenticated', true);

select is((select string_agg(right(id::text, 1), '' order by ord) from (select id, row_number() over () ord from public.get_feed()) f),
          'cba', 'without a sort, the day of the event decides, as before');
select is((select string_agg(right(id::text, 1), '' order by ord) from (select id, row_number() over () ord from public.get_feed(sort_by => 'occurred')) f),
          'cba', 'sorted by the event');
select is((select string_agg(right(id::text, 1), '' order by ord) from (select id, row_number() over () ord from public.get_feed(sort_by => 'created')) f),
          'abc', 'sorted by check-in time, the last one added is first');

-- Paging on each: the cursor is the time the feed is sorted by
select is((select cursor_time from public.get_feed(sort_by => 'created', page_size => 1)), '2026-11-03T10:00:00Z'::timestamptz, 'the cursor is the check-in time when sorted by it');
select is((select cursor_time from public.get_feed(page_size => 1)), '2026-03-01T10:00:00Z'::timestamptz, 'and the event time otherwise');
select is((select right(id::text, 1) from public.get_feed('2026-11-03T10:00:00Z', 'c0000000-0000-7000-8000-00000000000a', 1, 'created')), 'b', 'the second page by check-in time');
select is((select right(id::text, 1) from public.get_feed('2026-03-01T10:00:00Z', 'c0000000-0000-7000-8000-00000000000c', 1, 'occurred')), 'b', 'the second page by event time');

select * from finish();
rollback;
