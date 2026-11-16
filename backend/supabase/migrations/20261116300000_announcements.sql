-- A short message from the project owner that every user sees at the top of the feed, signed in or not.
-- Nobody writes through the API: the owner posts with scripts/post_announcement.sh, which runs as the database owner.
-- RLS is on with no policy, so the table is closed to clients; get_announcements() is the only way to read it.
create table public.announcements (
  id          uuid primary key default gen_random_uuid(),
  title_en    text not null check (char_length(title_en) between 1 and 120),
  body_en     text not null check (char_length(body_en) between 1 and 1000),
  title_de    text check (char_length(title_de) between 1 and 120),
  body_de     text check (char_length(body_de) between 1 and 1000),
  created_at  timestamptz not null default now(),
  expires_at  timestamptz,
  active      boolean not null default true,
  check ((title_de is null) = (body_de is null))
);
alter table public.announcements enable row level security;

-- Active, unexpired announcements, newest first. German fields are null when there is no translation; the apps fall back to English.
create function public.get_announcements()
returns table (id uuid, title_en text, body_en text, title_de text, body_de text, created_at timestamptz, expires_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select a.id, a.title_en, a.body_en, a.title_de, a.body_de, a.created_at, a.expires_at
  from public.announcements a
  where a.active and (a.expires_at is null or a.expires_at > now())
  order by a.created_at desc, a.id
  limit 5;
$$;
revoke execute on function public.get_announcements() from public;
grant execute on function public.get_announcements() to anon, authenticated;
