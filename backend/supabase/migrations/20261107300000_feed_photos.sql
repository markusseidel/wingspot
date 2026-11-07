-- Milestone 7f: photos for other people.
-- A photo can be seen by whoever can see its check-in, except that photos of sensitive aircraft
-- (military, government, concept §8) stay with their owner, because a photo can show the registration.
-- Clients get a signed URL from storage for each photo they can read; the app never lists the bucket.

create function private.can_view_photo(photo_checkin uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(private.can_view_checkin(photo_checkin), false)
     and (
       exists (select 1 from public.checkins c where c.id = photo_checkin and c.user_id = auth.uid())
       or not coalesce((
         select a.is_sensitive from public.checkins c
         join public.aircraft a on a.id = c.aircraft_id
         where c.id = photo_checkin
       ), false)
     );
$$;
grant execute on function private.can_view_photo(uuid) to anon, authenticated;

-- The rows: the same rule as before, plus the sensitive-aircraft exception.
drop policy "read if check-in visible" on public.checkin_photos;
create policy "read if photo visible" on public.checkin_photos for select to anon, authenticated
  using (private.can_view_photo(checkin_id));

-- The files: readable if a visible photo row points at them. Anonymous visitors get nothing.
create policy "photos: visible check-in, read" on storage.objects for select to authenticated
  using (
    bucket_id = 'photos'
    and exists (
      select 1 from public.checkin_photos p
      where p.storage_path = storage.objects.name and private.can_view_photo(p.checkin_id)
    )
  );

-- Reporting a photo follows the same rule as seeing it.
create or replace function public.report(report_kind text, report_target text, report_reason text default null)
returns text language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  v_id uuid;
  v_ok boolean := false;
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if report_kind is null or report_kind not in ('user', 'checkin', 'comment', 'photo') then
    return 'invalid_kind';
  end if;
  begin
    v_id := report_target::uuid;
  exception when others then
    return 'unknown_target';
  end;

  if report_kind = 'user' then
    v_ok := v_id <> uid and exists (select 1 from public.profiles p where p.id = v_id)
            and not coalesce(private.is_blocked(uid, v_id), false);
  elsif report_kind = 'checkin' then
    v_ok := coalesce(private.can_view_checkin(v_id), false);
  elsif report_kind = 'comment' then
    v_ok := exists (select 1 from public.comments m
                    where m.id = v_id and coalesce(private.can_view_checkin(m.checkin_id), false));
  else
    v_ok := exists (select 1 from public.checkin_photos ph
                    where ph.id = v_id and coalesce(private.can_view_photo(ph.checkin_id), false));
  end if;
  if not v_ok then
    return 'unknown_target';
  end if;

  if (select count(*) from public.reports r
      where r.reporter = uid and r.created_at > now() - interval '1 hour') >= 20 then
    return 'too_many';
  end if;
  if not exists (select 1 from public.reports r
                 where r.reporter = uid and r.target_type = report_kind and r.target_id = report_target
                   and r.status = 'open') then
    insert into public.reports (reporter, target_type, target_id, reason)
    values (uid, report_kind, report_target, left(report_reason, 1000));
  end if;
  return 'reported';
end;
$$;
revoke execute on function public.report(text, text, text) from public;
grant execute on function public.report(text, text, text) to authenticated;
