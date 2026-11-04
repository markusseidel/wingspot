-- Schema rules that access tests don't cover.
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

insert into public.aircraft (registration) values ('D-TEST');
select is(
  (select data_status from public.aircraft where registration = 'D-TEST'), 'user_submitted',
  'a new aircraft is not verified by default'
);

select is(
  (
    select count(*)::int
    from pg_constraint c
    where c.contype = 'f' and c.connamespace = 'public'::regnamespace
      and not exists (
        select 1 from pg_index i
        where i.indrelid = c.conrelid and i.indkey[0] = c.conkey[1]
      )
  ),
  0,
  'every foreign key has an index'
);

select * from finish();
rollback;
