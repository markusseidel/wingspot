-- Reviewing suggested spotting locations (docs/SPOTTING-LOCATIONS-PLAN.md, follow-up).
-- Who may do what is kept in staff_roles, so another person can be given a role later by adding a row. Roles map to
-- permissions in private.staff_permissions; the apps ask for the caller's permissions and show only what they allow.

create table public.staff_roles (
  user_id    uuid primary key references public.profiles on delete cascade,
  role       text not null check (role in ('founder', 'moderator')),
  -- Whether the role is shown as a label on the person's profile.
  show_label boolean not null default false,
  created_at timestamptz not null default now()
);
alter table public.staff_roles enable row level security;
revoke all on public.staff_roles from anon, authenticated;

-- The one place that says what a role may do. A new permission or role is added here.
create function private.staff_permissions(uid uuid) returns text[]
language sql stable security definer set search_path = '' as $$
  select coalesce((
    select case r.role
             when 'founder' then array['review_spots', 'manage_staff']
             when 'moderator' then array['review_spots']
           end
    from public.staff_roles r where r.user_id = uid
  ), array[]::text[]);
$$;
revoke execute on function private.staff_permissions(uuid) from public, anon, authenticated;

create function private.has_permission(uid uuid, permission text) returns boolean
language sql stable security definer set search_path = '' as $$
  select uid is not null and permission = any (private.staff_permissions(uid));
$$;
revoke execute on function private.has_permission(uuid, text) from public, anon, authenticated;

-- What the caller may do, e.g. {review_spots, manage_staff}. Empty for everyone else.
create function public.my_permissions() returns text[]
language sql stable security definer set search_path = '' as $$
  select private.staff_permissions(auth.uid());
$$;
revoke execute on function public.my_permissions() from public, anon;
grant execute on function public.my_permissions() to authenticated;

-- The role label of a person, when they chose to show it (the founder does): `founder`, or null.
create function public.staff_label(p_user uuid) returns text
language sql stable security definer set search_path = '' as $$
  select r.role from public.staff_roles r
  where r.user_id = p_user and r.show_label and not coalesce(private.is_blocked(auth.uid(), p_user), false);
$$;
revoke execute on function public.staff_label(uuid) from public;
grant execute on function public.staff_label(uuid) to anon, authenticated;

-- Who decided on a place, when, and why not.
alter table public.spotting_locations
  add column reviewed_by uuid,
  add column reviewed_at timestamptz,
  add column review_note text check (char_length(review_note) <= 300);

-- A rejected place is gone for everybody, its author too. The author sees only what still waits.
drop policy "read approved or own" on public.spotting_locations;
create policy "read approved or own" on public.spotting_locations for select to anon, authenticated
  using (status = 'approved' or (status = 'pending' and created_by = (select auth.uid())));

do $$
declare
  f record;
  v_def text;
  v_new text;
begin
  for f in
    select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private') and p.prokind = 'f' and pg_get_functiondef(p.oid) like '%spotting_locations%'
      and (pg_get_functiondef(p.oid) like '%or s.created_by = uid)%' or pg_get_functiondef(p.oid) like '%or s.created_by = auth.uid())%')
  loop
    v_def := pg_get_functiondef(f.oid);
    v_new := replace(replace(v_def,
      'or s.created_by = uid)', 'or (s.created_by = uid and s.status = ''pending''))'),
      'or s.created_by = auth.uid())', 'or (s.created_by = auth.uid() and s.status = ''pending''))');
    execute v_new;
  end loop;
end;
$$;

-- Places that wait for a decision, oldest first, with where they are and who suggested them.
create function public.pending_spots(p_limit integer default 50)
returns table (
  id integer, name text, latitude double precision, longitude double precision, description text, best_time text,
  facing text, tips text, legal_notes text, airport_id integer, airport_name text, airport_code text,
  author_id uuid, author_username text, author_name text, created_at timestamptz
)
language sql stable security definer set search_path = '' as $$
  select s.id, s.name, extensions.st_y(s.location::extensions.geometry), extensions.st_x(s.location::extensions.geometry),
         s.description, s.best_time, s.facing, s.tips, s.legal_notes, s.airport_id, a.name, coalesce(a.iata, a.icao),
         s.created_by, p.username, p.display_name, s.created_at
  from public.spotting_locations s
  join public.airports a on a.id = s.airport_id
  left join public.profiles p on p.id = s.created_by
  where private.has_permission(auth.uid(), 'review_spots') and s.status = 'pending'
  order by s.created_at
  limit greatest(least(coalesce(p_limit, 50), 200), 1);
$$;
revoke execute on function public.pending_spots(integer) from public, anon;
grant execute on function public.pending_spots(integer) to authenticated;

-- Approves or rejects a waiting place and tells its author. The note is shown to the author on a rejection.
create function public.review_spot(p_id integer, p_approve boolean, p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  v_spot public.spotting_locations;
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
begin
  if not private.has_permission(uid, 'review_spots') then
    return jsonb_build_object('status', 'rejected', 'code', 'not_allowed');
  end if;
  if p_approve is null or (v_note is not null and char_length(v_note) > 300) then
    return jsonb_build_object('status', 'rejected', 'code', 'invalid_request');
  end if;
  update public.spotting_locations s
     set status = case when p_approve then 'approved' else 'rejected' end,
         reviewed_by = uid, reviewed_at = now(), review_note = v_note
   where s.id = p_id and s.status = 'pending'
  returning * into v_spot;
  if not found then
    return jsonb_build_object('status', 'rejected', 'code', 'not_pending');
  end if;
  perform private.queue_notification(
    v_spot.created_by, case when p_approve then 'spot_approved' else 'spot_rejected' end, uid, null,
    v_spot.name || case when not p_approve and v_note is not null then E'\n' || v_note else '' end);
  return jsonb_build_object('status', case when p_approve then 'approved' else 'rejected' end, 'id', p_id);
end;
$$;
revoke execute on function public.review_spot(integer, boolean, text) from public, anon;
grant execute on function public.review_spot(integer, boolean, text) to authenticated;

-- The two new kinds. A decision on a place is not the same thing twice within the hour, so they skip the duplicate check.
alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check
  check (kind in ('follow', 'salute', 'comment', 'checkin', 'tagged', 'mention', 'reply', 'comment_like', 'tag_copy', 'friend_badge',
                  'spot_approved', 'spot_rejected'));

do $$
declare
  v_def text := pg_get_functiondef('private.queue_notification(uuid, text, uuid, uuid, text)'::regprocedure);
  v_new text;
begin
  v_new := replace(v_def, 'if notify_kind <> ''comment'' and exists (', 'if notify_kind not in (''comment'', ''spot_approved'', ''spot_rejected'') and exists (');
  if v_new = v_def then raise exception 'anchor not found in queue_notification'; end if;
  execute v_new;
end;
$$;
