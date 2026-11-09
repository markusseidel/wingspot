#!/usr/bin/env bash
# Makes (or resets) the demo account for App Review, with a second user to follow and a few check-ins, a comment and
# a salute, so the reviewer can try the feed, reporting, blocking and account deletion.
#
#   DEMO_PASSWORD='...' backend/scripts/seed-review-account.sh --local
#   DEMO_PASSWORD='...' backend/scripts/seed-review-account.sh --remote     (production: only when you mean it)
#
# The password comes from the environment so it never lands in the repo or the shell history of a pasted command.
# Run it again to reset the account after the reviewer deleted it. Sign in with: review@wingspot.site and the password.
set -euo pipefail

target="${1:-}"
case "$target" in
  --local) flags=() ;;
  --remote) flags=(--remote --yes) ;;
  *) echo "Usage: DEMO_PASSWORD=... $0 --local|--remote" >&2; exit 2 ;;
esac
: "${DEMO_PASSWORD:?Set DEMO_PASSWORD to the password for the demo account}"
if [ "${#DEMO_PASSWORD}" -lt 12 ] || [[ "$DEMO_PASSWORD" == *"'"* ]]; then
  echo "The password needs at least 12 characters and no single quote." >&2
  exit 2
fi
cd "$(dirname "$0")/.."

supabase db query ${flags[@]+"${flags[@]}"} --workdir . "
do \$seed\$
declare
  reviewer constant uuid := '00000000-0000-0000-0000-0000000a0001';
  pal      constant uuid := '00000000-0000-0000-0000-0000000a0002';
  fra integer; muc integer; ham integer;
  b738 text; a320 text;
  ac1 integer; ac2 integer; ac3 integer;
begin
  -- The reviewer can sign in with this password. The second user can't sign in at all.
  insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
                          raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                          confirmation_token, recovery_token, email_change, email_change_token_new)
  values (reviewer, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'review@wingspot.site',
          extensions.crypt('$DEMO_PASSWORD', extensions.gen_salt('bf')), now(),
          '{\"provider\":\"email\",\"providers\":[\"email\"]}', '{}', now(), now(), '', '', '', ''),
         (pal, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'planepal@wingspot.site',
          extensions.crypt(gen_random_uuid()::text, extensions.gen_salt('bf')), now(),
          '{\"provider\":\"email\",\"providers\":[\"email\"]}', '{}', now(), now(), '', '', '', '')
  on conflict (id) do update set encrypted_password = excluded.encrypted_password, updated_at = now()
  ;
  insert into auth.identities (id, user_id, provider, provider_id, identity_data, last_sign_in_at, created_at, updated_at)
  values (gen_random_uuid(), reviewer, 'email', reviewer::text,
          jsonb_build_object('sub', reviewer::text, 'email', 'review@wingspot.site', 'email_verified', true), now(), now(), now()),
         (gen_random_uuid(), pal, 'email', pal::text,
          jsonb_build_object('sub', pal::text, 'email', 'planepal@wingspot.site', 'email_verified', true), now(), now(), now())
  on conflict do nothing;

  update public.profiles set username = 'appreview', display_name = 'App Review' where id = reviewer;
  update public.profiles set username = 'planepal', display_name = 'Plane Pal' where id = pal;

  select id into fra from public.airports where iata = 'FRA';
  select id into muc from public.airports where iata = 'MUC';
  select id into ham from public.airports where iata = 'HAM';
  select icao_code into b738 from public.aircraft_types where icao_code = 'B738';
  select icao_code into a320 from public.aircraft_types where icao_code = 'A320';

  insert into public.aircraft (registration, type_icao) values
    ('D-ABCD', a320), ('D-AIZZ', a320), ('D-ABMA', b738)
  on conflict (registration) do nothing;
  select id into ac1 from public.aircraft where registration = 'D-ABCD';
  select id into ac2 from public.aircraft where registration = 'D-AIZZ';
  select id into ac3 from public.aircraft where registration = 'D-ABMA';

  delete from public.checkins where id::text like '00000000-0000-0000-0000-0000000b%';
  insert into public.checkins (id, user_id, kind, occurred_at, visibility, aircraft_id, airport_id, note) values
    ('00000000-0000-0000-0000-0000000b0001', reviewer, 'spotted', now() - interval '2 days', 'public',  ac1, fra, 'Morning arrival.'),
    ('00000000-0000-0000-0000-0000000b0002', reviewer, 'spotted', now() - interval '1 day',  'friends', ac3, muc, null),
    ('00000000-0000-0000-0000-0000000b0003', pal,      'spotted', now() - interval '20 hours', 'public', ac2, fra, 'Nice livery.'),
    ('00000000-0000-0000-0000-0000000b0004', pal,      'spotted', now() - interval '5 hours',  'public', ac3, ham, null);
  insert into public.follows (follower, followee) values (reviewer, pal), (pal, reviewer) on conflict do nothing;
  insert into public.comments (checkin_id, user_id, body) values
    ('00000000-0000-0000-0000-0000000b0003', reviewer, 'Great shot!'),
    ('00000000-0000-0000-0000-0000000b0001', pal, 'Welcome to Wingspot.');
  insert into public.salutes (checkin_id, user_id) values
    ('00000000-0000-0000-0000-0000000b0003', reviewer), ('00000000-0000-0000-0000-0000000b0001', pal)
  on conflict do nothing;
end
\$seed\$"
echo "Demo account ready: review@wingspot.site"
