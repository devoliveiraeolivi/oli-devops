#!/usr/bin/env sh
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
BASE="$HERE/../skills/dev-cycle"
fail() { echo "FAIL: $1" >&2; exit 1; }

for f in references/setup-gate.md references/review-gates.md references/pre-push-gate.md \
         references/finalize.md assets/pr-body-template.md assets/close-out-checklist.md; do
  [ -s "$BASE/$f" ] || fail "missing or empty: $f"
done
# Each reference references a concrete mechanism (no empty stubs)
grep -qi 'opus' "$BASE/references/review-gates.md" || fail "review-gates.md must pin Opus"
grep -qi 'security-review' "$BASE/references/review-gates.md" || fail "review-gates.md missing security sub-gate"
grep -qi 'MERGED' "$BASE/references/finalize.md" || fail "finalize.md must gate on MERGED state"
grep -qi 'pyproject\|package.json' "$BASE/references/pre-push-gate.md" || fail "pre-push-gate.md missing stack detection"
grep -qi 'main' "$BASE/references/setup-gate.md" || fail "setup-gate.md must require branch from main"
echo "PASS test_references"
