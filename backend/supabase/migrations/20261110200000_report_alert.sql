-- Tells the operator when a report comes in (App Store rule 1.2: act on reports within 24 hours).
-- The address of a chat webhook (Slack, Discord or Mattermost style) lives in the Vault under the name
-- report_webhook_url, set by hand. Without it nothing is called, so a fresh database and the tests stay quiet.
-- A failing webhook never stops a report from being saved.
create function private.alert_report() returns trigger language plpgsql security definer set search_path = '' as $$
declare
  webhook text;
  message text;
begin
  select s.decrypted_secret into webhook from vault.decrypted_secrets s where s.name = 'report_webhook_url';
  if webhook is not null then
    message := 'Wingspot: new report about a ' || new.target_type
      || case when coalesce(new.reason, '') <> '' then ': ' || left(new.reason, 200) else '' end
      || ' (id ' || left(new.id::text, 8) || '). Open reports: select * from reports where status = ''open''.';
    perform net.http_post(
      url := webhook,
      headers := jsonb_build_object('Content-Type', 'application/json'),
      body := jsonb_build_object('text', message, 'content', message),
      timeout_milliseconds := 5000
    );
  end if;
  return null;
exception when others then
  raise warning 'alert_report failed: %', sqlerrm;
  return null;
end;
$$;
revoke execute on function private.alert_report() from public;

create trigger reports_alert after insert on public.reports
  for each row execute function private.alert_report();
