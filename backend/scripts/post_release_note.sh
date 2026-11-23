#!/usr/bin/env bash
# Posts, lists or switches off the "What's new" text of one app build (Settings > What's new in the apps).
#
#   backend/scripts/post_release_note.sh --local|--remote post ios|android <version> <build> "Title" "- bullet one\n- bullet two" ["Titel (German)" "Text (German)"] [--release]
#   backend/scripts/post_release_note.sh --local|--remote list [ios|android]
#   backend/scripts/post_release_note.sh --local|--remote off ios|android <build>
#
# One call per platform: the builds have different numbers (iOS 2026112308, Android 2026112301). A change on both apps is two calls.
# The text is a few lines, one "- " bullet per line (write \n between them). No links, no formatting. Never write the name or rule of a
# hidden badge here: the table is readable by everyone. --release marks a store release instead of a beta. Without German text,
# German users see the English one. --remote is production: only when you mean it. Needs `supabase login`, nothing else.
set -euo pipefail

usage() { sed -n '2,11p' "$0" >&2; exit 2; }
target="${1:-}"; cmd="${2:-}"
case "$target" in
  --local) flags=() ;;
  --remote) flags=(--remote --yes) ;;
  *) usage ;;
esac
shift 2 || usage
cd "$(dirname "$0")/.."

two="''"
q() { printf "'%s'" "${1//\'/$two}"; }
run() { supabase db query ${flags[@]+"${flags[@]}"} --workdir . "$1"; }
platform_ok() { [[ "$1" == ios || "$1" == android ]] || { echo "The platform is ios or android." >&2; exit 2; }; }
# "\n" typed in a shell string becomes a real line break.
lines() { printf '%b' "$1"; }

case "$cmd" in
  post)
    [ $# -ge 5 ] || usage
    platform="$1"; version="$2"; build="$3"; title_en="$4"; body_en="$(lines "$5")"; shift 5
    platform_ok "$platform"
    [[ "$build" =~ ^[0-9]+$ ]] || { echo "The build is a number like 2026112308." >&2; exit 2; }
    kind="beta"; de_t="null"; de_b="null"
    if [ $# -ge 2 ] && [ "$1" != "--release" ]; then
      de_t="$(q "$1")"; de_b="$(q "$(lines "$2")")"; shift 2
    fi
    if [ "${1:-}" = "--release" ]; then kind="release"; shift; fi
    [ $# -eq 0 ] || usage
    run "insert into public.release_notes (platform, version, build, kind, title_en, body_en, title_de, body_de)
         values ($(q "$platform"), $(q "$version"), $build, $(q "$kind"), $(q "$title_en"), $(q "$body_en"), $de_t, $de_b)
         on conflict (platform, build) do update set version = excluded.version, kind = excluded.kind, title_en = excluded.title_en,
           body_en = excluded.body_en, title_de = excluded.title_de, body_de = excluded.body_de, active = true
         returning platform, version, build, kind, title_en;"
    ;;
  list)
    if [ $# -ge 1 ]; then platform_ok "$1"; where="where platform = $(q "$1")"; else where=""; fi
    run "select platform, build, version, kind, active, released_at, title_en from public.release_notes $where order by build desc limit 40;"
    ;;
  off)
    [ $# -eq 2 ] || usage
    platform_ok "$1"
    [[ "$2" =~ ^[0-9]+$ ]] || { echo "The build is a number." >&2; exit 2; }
    run "update public.release_notes set active = false where platform = $(q "$1") and build = $2 returning platform, build, title_en, active;"
    ;;
  *) usage ;;
esac
