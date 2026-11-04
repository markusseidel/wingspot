#!/bin/bash
# Fails if the app's text and the string catalog disagree, or if any text has no German translation.
# Usage: ios/scripts/check-strings.sh <derived data path of a finished app build>
set -euo pipefail

derived_data=$1
resources="$(dirname "$0")/../Wingspot/Resources"
catalog="$resources/Localizable.xcstrings"

stringsdata=()
while IFS= read -r file; do stringsdata+=("$file"); done \
  < <(find "$derived_data" -path '*/Wingspot.build/*' -name '*.stringsdata')
if [ "${#stringsdata[@]}" -eq 0 ]; then
  echo "No extracted strings found in $derived_data. Build the app first." >&2
  exit 1
fi

before=$(mktemp)
cp "$catalog" "$before"
xcrun xcstringstool sync "$catalog" --stringsdata "${stringsdata[@]}"
if ! diff -u "$before" "$catalog"; then
  echo "Localizable.xcstrings doesn't match the code. Review the changes above and commit them." >&2
  exit 1
fi

for file in "$catalog" "$resources/InfoPlist.xcstrings"; do
  missing=$(jq -r '.strings | to_entries[]
    | select(.value.localizations.de.stringUnit.state != "translated") | .key' "$file")
  if [ -n "$missing" ]; then
    printf 'Missing German text in %s:\n%s\n' "$file" "$missing" >&2
    exit 1
  fi
done
echo "Strings are complete in English and German."
