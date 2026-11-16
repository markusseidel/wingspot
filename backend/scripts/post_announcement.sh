#!/usr/bin/env bash
# Posts, lists or switches off the announcement every Wingspot user sees at the top of the feed.
#
#   backend/scripts/post_announcement.sh --local|--remote post "Title" "Body" ["Titel (German)" "Text (German)"] [--expires 2026-12-31]
#   backend/scripts/post_announcement.sh --local|--remote list
#   backend/scripts/post_announcement.sh --local|--remote off <id>
#
# --remote is production: only when you mean it. Without German text, German users see the English one.
# Nothing secret is needed here beyond being logged in to the Supabase CLI (`supabase login`).
set -euo pipefail

usage() { sed -n '2,10p' "$0" >&2; exit 2; }
target="${1:-}"; cmd="${2:-}"
case "$target" in
  --local) flags=() ;;
  --remote) flags=(--remote --yes) ;;
  *) usage ;;
esac
shift 2 || usage
cd "$(dirname "$0")/.."

# Doubles single quotes so text can be put inside an SQL string literal. Dollar-quoting would also work; this keeps it plain.
two="''"
q() { printf "'%s'" "${1//\'/$two}"; }
run() { supabase db query ${flags[@]+"${flags[@]}"} --workdir . "$1"; }

case "$cmd" in
  post)
    [ $# -ge 2 ] || usage
    title_en="$1"; body_en="$2"; shift 2
    title_de=""; body_de=""; expires=""
    if [ $# -ge 1 ] && [ "$1" != "--expires" ]; then
      [ $# -ge 2 ] || usage
      title_de="$1"; body_de="$2"; shift 2
    fi
    if [ "${1:-}" = "--expires" ]; then
      [ $# -eq 2 ] || usage
      [[ "$2" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "--expires takes a date like 2026-12-31" >&2; exit 2; }
      expires="$2"; shift 2
    fi
    [ $# -eq 0 ] || usage
    de_t="null"; de_b="null"; exp="null"
    [ -z "$title_de" ] || { de_t="$(q "$title_de")"; de_b="$(q "$body_de")"; }
    [ -z "$expires" ] || exp="$(q "$expires")::date::timestamptz"
    run "insert into public.announcements (title_en, body_en, title_de, body_de, expires_at)
         values ($(q "$title_en"), $(q "$body_en"), $de_t, $de_b, $exp) returning id, title_en, expires_at;"
    ;;
  list)
    run "select id, active, created_at, expires_at, title_en from public.announcements order by created_at desc limit 20;"
    ;;
  off)
    [ $# -eq 1 ] || usage
    [[ "$1" =~ ^[0-9a-f-]{36}$ ]] || { echo "That is not an announcement id." >&2; exit 2; }
    run "update public.announcements set active = false where id = '$1' returning id, title_en, active;"
    ;;
  *) usage ;;
esac
