-- Milestone 8b: a person's own data as one JSON document (GDPR access and portability).
-- Only rows that belong to the caller. Push tokens and other people's data are left out. Photo files
-- are not included, only the list of photos.
create function public.export_my_data()
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  result jsonb;
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select jsonb_build_object(
    'exported_at', now(),
    'profile', (select to_jsonb(p) from public.profiles p where p.id = uid),
    'notification_prefs', (select to_jsonb(n) - 'user_id' from public.notification_prefs n where n.user_id = uid),
    'checkins', coalesce((
      select jsonb_agg(
        (to_jsonb(c) - 'user_id' - 'location')
        || jsonb_build_object(
             'registration', a.registration,
             'airport_code', coalesce(ap.iata, ap.icao),
             'origin_code', coalesce(o.iata, o.icao),
             'destination_code', coalesce(d.iata, d.icao),
             'latitude', extensions.st_y(c.location::extensions.geometry),
             'longitude', extensions.st_x(c.location::extensions.geometry))
        order by c.occurred_at, c.id)
      from public.checkins c
      left join public.aircraft a on a.id = c.aircraft_id
      left join public.airports ap on ap.id = c.airport_id
      left join public.airports o on o.id = c.origin_id
      left join public.airports d on d.id = c.destination_id
      where c.user_id = uid
    ), '[]'::jsonb),
    'photos', coalesce((
      select jsonb_agg(jsonb_build_object('id', ph.id, 'checkin_id', ph.checkin_id, 'width', ph.width,
                                          'height', ph.height, 'position', ph.position) order by ph.checkin_id, ph.position)
      from public.checkin_photos ph join public.checkins c on c.id = ph.checkin_id
      where c.user_id = uid
    ), '[]'::jsonb),
    'comments_written', coalesce((
      select jsonb_agg(to_jsonb(m) - 'user_id' order by m.created_at, m.id)
      from public.comments m where m.user_id = uid
    ), '[]'::jsonb),
    'salutes_given', coalesce((
      select jsonb_agg(jsonb_build_object('checkin_id', s.checkin_id) order by s.checkin_id)
      from public.salutes s where s.user_id = uid
    ), '[]'::jsonb),
    'following', coalesce((
      select jsonb_agg(jsonb_build_object('username', p.username, 'since', f.created_at) order by f.created_at)
      from public.follows f join public.profiles p on p.id = f.followee where f.follower = uid
    ), '[]'::jsonb),
    'followers', coalesce((
      select jsonb_agg(jsonb_build_object('username', p.username, 'since', f.created_at) order by f.created_at)
      from public.follows f join public.profiles p on p.id = f.follower where f.followee = uid
    ), '[]'::jsonb),
    'blocked', coalesce((
      select jsonb_agg(jsonb_build_object('username', p.username) order by p.username)
      from public.blocks b join public.profiles p on p.id = b.blocked where b.blocker = uid
    ), '[]'::jsonb),
    'badges', coalesce((
      select jsonb_agg(to_jsonb(ub) - 'user_id' order by ub.badge_id)
      from public.user_badges ub where ub.user_id = uid
    ), '[]'::jsonb),
    'reports_filed', coalesce((
      select jsonb_agg(jsonb_build_object('target_type', r.target_type, 'target_id', r.target_id,
                                          'reason', r.reason, 'status', r.status, 'created_at', r.created_at)
                       order by r.created_at)
      from public.reports r where r.reporter = uid
    ), '[]'::jsonb),
    'devices', coalesce((
      select jsonb_agg(jsonb_build_object('platform', dv.platform, 'app_version', dv.app_version,
                                          'os_version', dv.os_version, 'locale', dv.locale,
                                          'last_seen_at', dv.last_seen_at) order by dv.last_seen_at)
      from public.devices dv where dv.user_id = uid
    ), '[]'::jsonb),
    'entitlements', coalesce((
      select jsonb_agg(jsonb_build_object('entitlement', e.entitlement, 'store', e.store, 'product_id', e.product_id,
                                          'status', e.status, 'expires_at', e.expires_at) order by e.entitlement)
      from public.entitlements e where e.user_id = uid
    ), '[]'::jsonb)
  ) into result;
  return result;
end;
$$;
revoke execute on function public.export_my_data() from public;
grant execute on function public.export_my_data() to authenticated;
