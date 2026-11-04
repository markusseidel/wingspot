-- Reference data bucket: public downloads, no client listing or uploads.
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

select is((select public from storage.buckets where id = 'refdata'), true, 'the refdata bucket is public');

insert into storage.objects (bucket_id, name) values ('refdata', 'test/refdata.sqlite');

set local role anon;
select is((select count(*)::int from storage.objects where bucket_id = 'refdata'), 0, 'anonymous clients cannot list snapshots');
select throws_ok(
  $$ insert into storage.objects (bucket_id, name) values ('refdata', 'test/anon.sqlite') $$,
  '42501', null, 'anonymous clients cannot upload'
);
reset role;

set local role authenticated;
select is((select count(*)::int from storage.objects where bucket_id = 'refdata'), 0, 'signed-in clients cannot list snapshots');
select throws_ok(
  $$ insert into storage.objects (bucket_id, name) values ('refdata', 'test/user.sqlite') $$,
  '42501', null, 'signed-in clients cannot upload'
);
reset role;

select * from finish();
rollback;
