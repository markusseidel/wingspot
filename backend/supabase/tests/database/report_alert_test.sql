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

-- What the message says
insert into auth.users (id, aud, role, email) values
  ('00000000-0000-0000-0000-000000000d01', 'authenticated', 'authenticated', 'author@example.test'),
  ('00000000-0000-0000-0000-000000000d02', 'authenticated', 'authenticated', 'reporter@example.test');
update public.profiles set username = 'author_user' where id = '00000000-0000-0000-0000-000000000d01';
update public.profiles set username = 'reporter_user' where id = '00000000-0000-0000-0000-000000000d02';
insert into public.aircraft_types (icao_code, manufacturer, model) values ('A321', 'Airbus', 'A321');
insert into public.checkins (id, user_id, kind, occurred_at, visibility, type_icao)
values ('d0000000-0000-7000-8000-000000000001', '00000000-0000-0000-0000-000000000d01', 'spotted', now(), 'public', 'A321');
insert into public.comments (id, checkin_id, user_id, body)
values ('d0000000-0000-7000-8000-000000000002', 'd0000000-0000-7000-8000-000000000001', '00000000-0000-0000-0000-000000000d01', 'a rude comment');

insert into public.reports (id, reporter, target_type, target_id, reason) values
  ('e0000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000d02', 'checkin', 'd0000000-0000-7000-8000-000000000001', 'spam'),
  ('e0000000-0000-4000-8000-000000000002', null, 'comment', 'd0000000-0000-7000-8000-000000000002', null),
  ('e0000000-0000-4000-8000-000000000003', null, 'checkin', 'not-an-id', 'spam');
select like((select private.report_alert_text(r) from public.reports r where r.id = 'e0000000-0000-4000-8000-000000000001'),
  '%about a checkin by @author_user (spotted A321)%Reason: spam%Reported by @reporter_user%dashboard%',
  'a check-in report names the author, what it shows, the reason, the reporter and links to the table');
select like((select private.report_alert_text(r) from public.reports r where r.id = 'e0000000-0000-4000-8000-000000000002'),
  '%about a comment by @author_user ("a rude comment")%Reason: none given%',
  'a comment report quotes the comment, and says when no reason was given');
select like((select private.report_alert_text(r) from public.reports r where r.id = 'e0000000-0000-4000-8000-000000000003'),
  '%already deleted or not found%', 'a report about something that is gone still gets a message');
select ok(not has_function_privilege('authenticated', 'private.report_alert_text(public.reports)', 'execute'), 'clients cannot call the text function');

select * from finish();
rollback;
