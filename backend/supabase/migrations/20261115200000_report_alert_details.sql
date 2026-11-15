-- The report alert says what was reported, by whom and by whom it was reported, and links to the reports table in the
-- Supabase dashboard. The text is built by a function of its own so it can be tested. It uses Slack's link format,
-- which chat apps that ignore it show as plain text.
create function private.report_alert_text(r public.reports) returns text
language plpgsql stable security definer set search_path = '' as $$
declare
  what text := r.target_type;
  who text;
  detail text;
  v_id uuid;
begin
  begin
    v_id := r.target_id::uuid;
  exception when others then
    v_id := null;
  end;

  if v_id is not null then
    if r.target_type = 'user' then
      select '@' || p.username into who from public.profiles p where p.id = v_id;
    elsif r.target_type = 'checkin' then
      select '@' || p.username,
             case c.kind
               when 'flown' then 'flight ' || coalesce(coalesce(o.iata, o.icao), '?') || ' → ' || coalesce(coalesce(d.iata, d.icao), '?')
               when 'airport' then 'airport visit ' || coalesce(coalesce(ap.iata, ap.icao), '?')
               else 'spotted ' || coalesce(a.registration, c.type_icao, '?')
             end
        into who, detail
      from public.checkins c
      join public.profiles p on p.id = c.user_id
      left join public.aircraft a on a.id = c.aircraft_id
      left join public.airports ap on ap.id = c.airport_id
      left join public.airports o on o.id = c.origin_id
      left join public.airports d on d.id = c.destination_id
      where c.id = v_id;
    elsif r.target_type = 'comment' then
      select '@' || p.username, '"' || left(replace(m.body, E'\n', ' '), 140) || '"' into who, detail
      from public.comments m join public.profiles p on p.id = m.user_id where m.id = v_id;
    elsif r.target_type = 'photo' then
      select '@' || p.username, 'on ' || c.kind::text || ' check-in' into who, detail
      from public.checkin_photos ph
      join public.checkins c on c.id = ph.checkin_id
      join public.profiles p on p.id = c.user_id where ph.id = v_id;
    end if;
  end if;

  return 'Wingspot: new report about a ' || what
    || coalesce(' by ' || who, '') || coalesce(' (' || detail || ')', ' (already deleted or not found)')
    || E'\nReason: ' || coalesce(nullif(left(r.reason, 200), ''), 'none given')
    || coalesce(E'\nReported by @' || (select p.username from public.profiles p where p.id = r.reporter), '')
    || E'\n<https://supabase.com/dashboard/project/gsfeuxowjymdqbopcpdo/editor/19081?schema=public|Open the reports table>'
    || ' (id ' || left(r.id::text, 8) || ', status open)';
end;
$$;
revoke execute on function private.report_alert_text(public.reports) from public, anon, authenticated;

create or replace function private.alert_report() returns trigger language plpgsql security definer set search_path = '' as $$
declare
  webhook text;
  message text;
begin
  select s.decrypted_secret into webhook from vault.decrypted_secrets s where s.name = 'report_webhook_url';
  if webhook is not null then
    message := private.report_alert_text(new);
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
