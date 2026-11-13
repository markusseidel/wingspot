-- Android push: notifications now go to Android devices too. An Android device registers its Firebase (FCM) token with
-- register_device(platform 'android'). The send-push function reads each device's platform and sends through FCM for
-- Android and through APNs for iOS. Nothing else about who is notified changes.

create or replace function private.queue_notification(to_user uuid, notify_kind text, from_user uuid, for_checkin uuid, text_snippet text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if to_user is null or to_user = from_user then return; end if;
  if private.is_blocked(to_user, from_user) then return; end if;
  if not coalesce((
    select case notify_kind when 'follow' then p.new_followers when 'salute' then p.salutes when 'comment' then p.comments
                     when 'checkin' then p.followed_checkins end
    from public.notification_prefs p where p.user_id = to_user
  ), true) then return; end if;
  if not exists (
    select 1 from public.devices d where d.user_id = to_user and d.platform in ('ios', 'android') and d.push_token is not null
  ) then return; end if;
  if (select count(*) from public.notifications n
      where n.recipient = to_user and n.created_at > now() - interval '24 hours') >= 30 then return; end if;
  if notify_kind <> 'comment' and exists (
    select 1 from public.notifications n
    where n.recipient = to_user and n.kind = notify_kind and n.actor = from_user
      and n.checkin_id is not distinct from for_checkin and n.created_at > now() - interval '1 hour'
  ) then return; end if;
  insert into public.notifications (recipient, kind, actor, checkin_id, snippet)
  values (to_user, notify_kind, from_user, for_checkin, text_snippet);
end;
$$;

drop function public.claim_notifications(integer);
create function public.claim_notifications(batch_size integer default 50)
returns table (
  id uuid, kind text, actor_id uuid, actor_username text, actor_name text, checkin_id uuid,
  subject text, snippet text, devices jsonb, checkin_kind text
)
language plpgsql security definer set search_path = '' as $$
begin
  update public.notifications n set sent_at = now()
  where n.sent_at is null and (n.created_at < now() - interval '1 day' or n.attempts >= 5);

  return query
  with picked as (
    select n.id from public.notifications n
    where n.sent_at is null and (n.claimed_at is null or n.claimed_at < now() - interval '5 minutes')
    order by n.created_at
    limit greatest(least(coalesce(batch_size, 50), 100), 1)
    for update skip locked
  ), marked as (
    update public.notifications n set claimed_at = now(), attempts = n.attempts + 1
    from picked where n.id = picked.id
    returning n.id, n.recipient, n.kind, n.actor, n.checkin_id, n.snippet
  )
  select
    m.id, m.kind, m.actor, p.username, p.display_name, m.checkin_id,
    (select case
              when c.kind = 'flown' then coalesce(o.iata, o.icao) || ' → ' || coalesce(d.iata, d.icao)
              when c.kind = 'airport' then coalesce(ap.iata, ap.icao)
              else coalesce(case when a.is_sensitive and c.user_id <> m.recipient then null else a.registration end,
                            c.type_icao, a.type_icao, ap.iata, ap.icao)
            end
     from public.checkins c
     left join public.aircraft a on a.id = c.aircraft_id
     left join public.airports ap on ap.id = c.airport_id
     left join public.airports o on o.id = c.origin_id
     left join public.airports d on d.id = c.destination_id
     where c.id = m.checkin_id),
    m.snippet,
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', dv.id, 'token', dv.push_token, 'env', coalesce(dv.push_env, 'production'), 'locale', dv.locale, 'platform', dv.platform))
      from public.devices dv
      where dv.user_id = m.recipient and dv.platform in ('ios', 'android') and dv.push_token is not null
    ), '[]'::jsonb),
    (select c.kind::text from public.checkins c where c.id = m.checkin_id)
  from marked m
  join public.profiles p on p.id = m.actor;
end;
$$;

revoke execute on function public.claim_notifications(integer) from public, anon, authenticated;
grant execute on function public.claim_notifications(integer) to service_role;
