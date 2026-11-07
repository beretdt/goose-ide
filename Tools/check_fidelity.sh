#!/usr/bin/env bash
# Compares this project's interpreter with the reference Goose compiler.
#
#   Tools/check_fidelity.sh [directory-of-.goose-files]
#
# The reference binary comes from $GOOSE_REFERENCE, defaulting to the local
# upstream checkout. A file the reference rejects is skipped, since it is
# outside the subset this interpreter covers.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GOOSE_REFERENCE="${GOOSE_REFERENCE:-$HOME/goose-upstream/build-rel/goose}"
DIRECTORY="${1:-$ROOT/Tests/Fixtures}"

if [[ ! -x "$GOOSE_REFERENCE" ]]; then
  echo "no reference compiler at $GOOSE_REFERENCE" >&2
  exit 2
fi

GOOSECTL="$ROOT/.build/debug/goosectl"
if [[ ! -x "$GOOSECTL" ]]; then
  echo "build first: swift build" >&2
  exit 2
fi

checked=0
skipped=0
failed=0

for file in "$DIRECTORY"/*.goose; do
  [[ -e "$file" ]] || continue

  expected="$("$GOOSE_REFERENCE" run "$file" 2>/dev/null)"
  if [[ $? -ne 0 ]]; then
    skipped=$((skipped + 1))
    continue
  fi

  actual="$("$GOOSECTL" run "$file" 2>/tmp/goosectl-error)"
  if [[ $? -ne 0 ]]; then
    echo "FAIL $(basename "$file") — $(cat /tmp/goosectl-error)"
    failed=$((failed + 1))
    continue
  fi

  checked=$((checked + 1))
  if [[ "$expected" != "$actual" ]]; then
    echo "FAIL $(basename "$file")"
    diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") | head -20
    failed=$((failed + 1))
  fi
done

echo "checked $checked, skipped $skipped, failed $failed"
[[ $failed -eq 0 ]]
