#!/usr/bin/env sh
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
rc=0
for t in "$HERE"/test_*.sh; do
  echo "=== $t ==="
  sh "$t" || rc=1
done
[ -s "$HERE/../README.md" ] || { echo "FAIL: README.md missing" >&2; rc=1; }
grep -qi 'superpowers' "$HERE/../README.md" 2>/dev/null || { echo "FAIL: README must declare superpowers dependency" >&2; rc=1; }
[ "$rc" -eq 0 ] && echo "ALL GREEN" || echo "SUITE FAILED"
exit $rc
