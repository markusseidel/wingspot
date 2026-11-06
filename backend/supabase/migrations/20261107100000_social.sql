-- Milestone 7a: sharing, the feed, reports and a word filter for comments.
-- The social tables and their access rules already exist (follows, salutes, comments, blocks). This adds
-- what is missing to use them: the account's sharing choice, a feed query, counts, and reporting.

-- Sharing ------------------------------------------------------------------------------------
-- The visibility a check-in gets when the app doesn't send one. New accounts share nothing.
alter table public.profiles
  add column default_visibility text not null default 'private'
  check (default_visibility in ('public', 'friends', 'private'));
grant update (default_visibility) on public.profiles to authenticated;

-- The account's own choice can be read through get_profile, like post_delay_minutes.
drop function public.get_profile(uuid);
create function public.get_profile(target uuid)
returns table (id uuid, home_airport integer, post_delay_minutes integer, default_visibility text)
language sql stable security definer set search_path = '' as $$
  select
    p.id,
    case when private.can_view_profile_content(p.id) then p.home_airport end,
    case when p.id = auth.uid() then p.post_delay_minutes end,
    case when p.id = auth.uid() then p.default_visibility end
  from public.profiles p
  where p.id = target and not coalesce(private.is_blocked(auth.uid(), p.id), false);
$$;
revoke execute on function public.get_profile(uuid) from public;
grant execute on function public.get_profile(uuid) to anon, authenticated;

-- Sets the sharing choice, and with `apply_to_existing` changes every earlier check-in of the caller too.
-- Returns how many earlier check-ins changed.
create function public.set_sharing(new_default text, apply_to_existing boolean default false)
returns integer language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  changed integer := 0;
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if new_default is null or new_default not in ('public', 'friends', 'private') then
    raise exception 'invalid_visibility' using errcode = '22023';
  end if;
  update public.profiles set default_visibility = new_default where id = uid;
  if apply_to_existing then
    update public.checkins set visibility = new_default where user_id = uid and visibility <> new_default;
    get diagnostics changed = row_count;
  end if;
  return changed;
end;
$$;
revoke execute on function public.set_sharing(text, boolean) from public;
grant execute on function public.set_sharing(text, boolean) to authenticated;

-- check-ins sent without a visibility now follow the sharing choice
create or replace function public.sync_checkins(items jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  item jsonb;
  results jsonb := '[]'::jsonb;
  v_id uuid;
  v_registration text;
  v_type text;
  v_airport integer;
  v_kind text;
  v_context text;
  v_origin integer;
  v_destination integer;
  v_flight text;
  v_cabin text;
  v_seat text;
  v_distance integer;
  v_latitude double precision;
  v_longitude double precision;
  v_occurred timestamptz;
  v_visibility text;
  v_default_visibility text;
  v_aircraft integer;
  v_inserted integer;
  v_owner uuid;
  engine jsonb := '{}'::jsonb;
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if jsonb_typeof(items) is distinct from 'array' then
    raise exception 'items must be an array' using errcode = '22023';
  end if;
  if jsonb_array_length(items) > 50 then
    raise exception 'at most 50 items per call' using errcode = '22023';
  end if;

  -- A check-in the app sends without a visibility gets the account's sharing choice, which starts as private.
  select p.default_visibility into v_default_visibility from public.profiles p where p.id = uid;
  v_default_visibility := coalesce(v_default_visibility, 'private');

  for item in select value from jsonb_array_elements(items) loop
    v_id := null;
    begin
      v_id := (item ->> 'id')::uuid;

      v_kind := item ->> 'kind';
      if v_kind is null or v_kind not in ('spotted', 'airport', 'flown') then
        results := results || jsonb_build_object('id', v_id, 'status', 'rejected', 'code', 'unsupported_kind');
        continue;
      end if;

      v_registration := nullif(item ->> 'registration', '');
      v_type := nullif(item ->> 'type_icao', '');
      if v_kind = 'airport' then
        -- A visit is about the airport only. Any aircraft fields are ignored.
        v_registration := null;
        v_type := null;
      end if;
      if v_kind = 'spotted' and v_registration is null and v_type is null then
        results := results || jsonb_build_object('id', v_id, 'status', 'rejected', 'code', 'missing_aircraft');
        continue;
      end if;
      if v_registration is not null and v_registration !~ '^[A-Z0-9]{1,6}(-[A-Z0-9]{1,6})?$' then
        results := results || jsonb_build_object('id', v_id, 'status', 'rejected', 'code', 'invalid_registration');
        continue;
      end if;

      v_occurred := (item ->> 'occurred_at')::timestamptz;
      if v_occurred is null or v_occurred > now() + interval '1 day' then
        results := results || jsonb_build_object('id', v_id, 'status', 'rejected', 'code', 'invalid_time');
        continue;
      end if;

      if v_type is not null
         and not exists (select 1 from public.aircraft_types t where t.icao_code = v_type) then
        results := results || jsonb_build_object('id', v_id, 'status', 'rejected', 'code', 'unknown_type');
        continue;
      end if;

      v_airport := (item ->> 'airport_id')::integer;
      if v_airport is not null
         and not exists (select 1 from public.airports a where a.id = v_airport) then
        results := results || jsonb_build_object('id', v_id, 'status', 'rejected', 'code', 'unknown_airport');
        continue;
      end if;

      if v_kind = 'airport' and v_airport is null then
        results := results || jsonb_build_object('id', v_id, 'status', 'rejected', 'code', 'missing_airport');
        continue;
      end if;

      v_context := case when v_kind = 'airport' then nullif(item ->> 'context', '') end;
      if v_context is not null
         and v_context not in ('spotting', 'departing', 'arriving', 'transit', 'working', 'museum') then
        results := results || jsonb_build_object('id', v_id, 'status', 'rejected', 'code', 'invalid_context');
        continue;
      end if;

      v_origin := null; v_destination := null; v_flight := null; v_cabin := null; v_seat := null; v_distance := null;
      if v_kind = 'flown' then
        v_origin := (item ->> 'origin_id')::integer;
        v_destination := (item ->> 'destination_id')::integer;
        if v_origin is null or v_destination is null then
          results := results || jsonb_build_object('id', v_id, 'status', 'rejected', 'code', 'missing_route');
          continue;
        end if;
        if v_origin = v_destination then
          results := results || jsonb_build_object('id', v_id, 'status', 'rejected', 'code', 'invalid_route');
          continue;
        end if;
        select round(extensions.st_distance(o.location, d.location) / 1000)::integer into v_distance
        from public.airports o, public.airports d where o.id = v_origin and d.id = v_destination;
        if not found then
          results := results || jsonb_build_object('id', v_id, 'status', 'rejected', 'code', 'unknown_airport');
          continue;
        end if;
        v_flight := upper(nullif(replace(item ->> 'flight_number', ' ', ''), ''));
        if v_flight is not null and v_flight !~ '^[A-Z0-9]{2}[0-9]{1,4}[A-Z]?$' then
          results := results || jsonb_build_object('id', v_id, 'status', 'rejected', 'code', 'invalid_flight_number');
          continue;
        end if;
        v_cabin := nullif(item ->> 'cabin', '');
        if v_cabin is not null and v_cabin not in ('economy', 'premium_economy', 'business', 'first') then
          results := results || jsonb_build_object('id', v_id, 'status', 'rejected', 'code', 'invalid_cabin');
          continue;
        end if;
        v_seat := upper(nullif(item ->> 'seat', ''));
        if v_seat is not null and v_seat !~ '^[0-9]{1,3}[A-Z]$' then
          results := results || jsonb_build_object('id', v_id, 'status', 'rejected', 'code', 'invalid_seat');
          continue;
        end if;
      end if;

      v_latitude := (item ->> 'latitude')::double precision;
      v_longitude := (item ->> 'longitude')::double precision;
      if (v_latitude is null) <> (v_longitude is null)
         or v_latitude not between -90 and 90 or v_longitude not between -180 and 180 then
        results := results || jsonb_build_object('id', v_id, 'status', 'rejected', 'code', 'invalid_location');
        continue;
      end if;

      v_visibility := coalesce(item ->> 'visibility', v_default_visibility);
      if v_visibility not in ('public', 'friends', 'private') then
        results := results || jsonb_build_object('id', v_id, 'status', 'rejected', 'code', 'invalid_visibility');
        continue;
      end if;

      v_aircraft := null;
      if v_registration is not null then
        insert into public.aircraft (registration, data_status, country_code)
        values (v_registration, 'user_submitted', private.register_country(v_registration))
        on conflict (registration) do nothing;
        select a.id into v_aircraft from public.aircraft a where a.registration = v_registration;
      end if;

      insert into public.checkins (id, user_id, kind, occurred_at, aircraft_id, type_icao, airport_id,
                                   visit_context, origin_id, destination_id, flight_number, cabin_class, seat,
                                   distance_km, location, visibility)
      values (v_id, uid, v_kind::public.checkin_kind, v_occurred, v_aircraft, v_type, v_airport, v_context,
              v_origin, v_destination, v_flight, v_cabin, v_seat, v_distance,
              case when v_latitude is null then null
                   else extensions.st_makepoint(v_longitude, v_latitude)::extensions.geography end,
              v_visibility)
      on conflict (id) do nothing;
      get diagnostics v_inserted = row_count;

      if v_inserted = 0 then
        -- Already stored. That is fine if it is this user's own earlier upload.
        select c.user_id into v_owner from public.checkins c where c.id = v_id;
        if v_owner is distinct from uid then
          results := results || jsonb_build_object('id', v_id, 'status', 'rejected', 'code', 'id_taken');
          continue;
        end if;
      end if;

      results := results || jsonb_build_object('id', v_id, 'status', 'stored');
    exception
      when data_exception or not_null_violation or check_violation then
        -- A malformed field. The item's partial writes are rolled back.
        results := results || jsonb_build_object('id', v_id, 'status', 'rejected', 'code', 'invalid_request');
    end;
  end loop;

  -- Badges and XP come after the check-ins are stored. If they fail, the upload still succeeds and
  -- the phone gets the same answer as before, so a broken rule can never block sync.
  begin
    engine := private.evaluate_badges(uid);
  exception when others then
    raise warning 'badge evaluation failed: %', sqlerrm;
    engine := '{}'::jsonb;
  end;

  return jsonb_build_object('results', results) || engine;
end;
$$;

revoke execute on function public.sync_checkins(jsonb) from public;
grant execute on function public.sync_checkins(jsonb) to authenticated;

-- Feed -----------------------------------------------------------------------------------------
-- Check-ins of the people the caller follows, and their own, newest first. It runs as the caller, so the
-- existing rules decide what is visible: visibility, private profiles, blocks and the post delay. The same
-- rules cut the counts. Page with the last row's occurred_at and id: keyset paging never repeats or skips.
-- A check-in that becomes visible later, after a post delay, shows up after a refresh from the top.
-- The registration of a sensitive aircraft is hidden from other people. Raw location is never returned.
create function public.get_feed(before_time timestamptz default null, before_id uuid default null,
                                page_size integer default 30)
returns table (
  id uuid, user_id uuid, username text, display_name text, kind public.checkin_kind,
  occurred_at timestamptz, registration text, type_icao text, type_name text,
  airport_id integer, airport_code text, origin_code text, destination_code text,
  flight_number text, distance_km integer, salutes integer, comments integer, saluted boolean
)
language sql stable security invoker set search_path = '' as $$
  select
    c.id, c.user_id, p.username, p.display_name, c.kind, c.occurred_at,
    case when a.is_sensitive and c.user_id <> auth.uid() then null else a.registration end,
    coalesce(c.type_icao, a.type_icao),
    t.manufacturer || ' ' || t.model,
    c.airport_id, coalesce(ap.iata, ap.icao),
    coalesce(o.iata, o.icao), coalesce(d.iata, d.icao),
    c.flight_number, c.distance_km,
    (select count(*)::integer from public.salutes s where s.checkin_id = c.id),
    (select count(*)::integer from public.comments m where m.checkin_id = c.id),
    exists (select 1 from public.salutes s where s.checkin_id = c.id and s.user_id = auth.uid())
  from public.checkins c
  join public.profiles p on p.id = c.user_id
  left join public.aircraft a on a.id = c.aircraft_id
  left join public.aircraft_types t on t.icao_code = coalesce(c.type_icao, a.type_icao)
  left join public.airports ap on ap.id = c.airport_id
  left join public.airports o on o.id = c.origin_id
  left join public.airports d on d.id = c.destination_id
  where (c.user_id = auth.uid()
         or exists (select 1 from public.follows f where f.follower = auth.uid() and f.followee = c.user_id))
    and (before_time is null or (c.occurred_at, c.id) < (before_time, before_id))
  order by c.occurred_at desc, c.id desc
  limit least(greatest(coalesce(page_size, 30), 1), 50);
$$;
revoke execute on function public.get_feed(timestamptz, uuid, integer) from public;
grant execute on function public.get_feed(timestamptz, uuid, integer) to authenticated;

-- Reports ----------------------------------------------------------------------------------------
-- Reports have no client access. This is the one way in: it checks that the caller can see the target.
alter table public.reports add column created_at timestamptz not null default now();
create index reports_status_idx on public.reports (status, created_at);

-- Returns 'reported', or 'unknown_target' (it doesn't exist or the caller can't see it), 'invalid_kind' or
-- 'too_many' (20 in an hour). Reporting the same target again while the first report is open does nothing.
create function public.report(report_kind text, report_target text, report_reason text default null)
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
                    where ph.id = v_id and coalesce(private.can_view_checkin(ph.checkin_id), false));
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

-- Word filter for comments ---------------------------------------------------------------------
-- Whole words only, any case. The project owner can add words with plain SQL: insert into private.blocked_words.
create table private.blocked_words (word text primary key check (word ~ '^[a-zäöüß]+$'));
alter table private.blocked_words enable row level security;
insert into private.blocked_words (word) values
  ('fuck'), ('shit'), ('bitch'), ('asshole'), ('arschloch'), ('scheisse'), ('scheiße'), ('hurensohn'), ('wichser');

create function private.check_comment() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if exists (
    select 1 from private.blocked_words w
    where lower(new.body) ~ ('(^|[^[:alpha:]])' || w.word || '([^[:alpha:]]|$)')
  ) then
    raise exception 'comment_not_allowed' using errcode = '23514';
  end if;
  return new;
end;
$$;
create trigger comments_word_filter before insert on public.comments
  for each row execute function private.check_comment();
