-- What's new: a short text per app build, shown in Settings. One row per platform and build, English and German, posted by the owner
-- with scripts/post_release_note.sh (runs as the database owner). Like the announcements: RLS on with no policy, so the table is
-- closed to clients and get_release_notes() is the only way to read it. The notes hold nothing private, so signed-out users read too.
create table public.release_notes (
  id          uuid primary key default gen_random_uuid(),
  platform    text not null check (platform in ('ios', 'android')),
  version     text not null check (char_length(version) between 1 and 20),
  build       bigint not null check (build > 0),
  kind        text not null default 'beta' check (kind in ('beta', 'release')),
  title_en    text not null check (char_length(title_en) between 1 and 120),
  body_en     text not null check (char_length(body_en) between 1 and 1000),
  title_de    text check (char_length(title_de) between 1 and 120),
  body_de     text check (char_length(body_de) between 1 and 1000),
  released_at timestamptz not null default now(),
  active      boolean not null default true,
  unique (platform, build),
  check ((title_de is null) = (body_de is null))
);
alter table public.release_notes enable row level security;

-- Active notes of one platform, newest build first. German fields are null when there is no translation; the apps fall back to English.
create function public.get_release_notes(p_platform text, p_limit int default 30)
returns table (id uuid, version text, build bigint, kind text, title_en text, body_en text, title_de text, body_de text, released_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select r.id, r.version, r.build, r.kind, r.title_en, r.body_en, r.title_de, r.body_de, r.released_at
  from public.release_notes r
  where r.active and r.platform = p_platform
  order by r.build desc
  limit least(greatest(coalesce(p_limit, 30), 1), 50);
$$;
revoke execute on function public.get_release_notes(text, int) from public;
grant execute on function public.get_release_notes(text, int) to anon, authenticated;
