-- Sign in with Apple: the refresh token Apple gave when someone signed in, kept only so it can be revoked when the
-- account is deleted (Apple requires that). Nobody but the server can read or write it: row level security is on with
-- no policies, and the client roles have no privileges. Deleting the user removes the row.
create table public.apple_tokens (
  user_id       uuid primary key references auth.users on delete cascade,
  refresh_token text not null,
  created_at    timestamptz not null default now()
);
alter table public.apple_tokens enable row level security;
revoke all on public.apple_tokens from anon, authenticated, public;
