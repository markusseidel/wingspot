-- A new report calls the operator's webhook if there is one, and is saved either way.
-- Run with: supabase test db --workdir backend
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

select has_trigger('public', 'reports', 'reports_alert', 'new reports trigger the alert');
insert into public.reports (target_type, target_id, reason) values ('checkin', 'x1', 'spam');
select is((select count(*)::int from public.reports where target_id = 'x1'), 1, 'a report is saved without a webhook');

select vault.create_secret('http://127.0.0.1:9/none', 'report_webhook_url');
insert into public.reports (target_type, target_id, reason) values ('checkin', 'x2', repeat('long ', 100));
select is((select count(*)::int from public.reports where target_id = 'x2'), 1, 'and with one, even a long reason');
select ok(not has_function_privilege('authenticated', 'private.alert_report()', 'execute'), 'clients cannot call the alert function');

select * from finish();
rollback;
