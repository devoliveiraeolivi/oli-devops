#!/usr/bin/env sh
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
BASE="$HERE/../skills/dev-cycle"
fail() { echo "FAIL: $1" >&2; exit 1; }

for f in references/setup-gate.md references/review-gates.md references/pre-push-gate.md \
         references/finalize.md references/model-tiers.md \
         assets/pr-body-template.md assets/close-out-checklist.md; do
  [ -s "$BASE/$f" ] || fail "missing or empty: $f"
done
# Model tiers (full/light) documented as the single source of truth
MT="$BASE/references/model-tiers.md"
grep -qiF 'full'  "$MT" || fail "model-tiers.md must document the full tier"
grep -qiF 'light' "$MT" || fail "model-tiers.md must document the light tier"
grep -qi  'conductor' "$MT" || fail "model-tiers.md must state the conductor role"
grep -qi  'sonnet' "$MT" || fail "model-tiers.md must mention Sonnet"
grep -qi  'opus'   "$MT" || fail "model-tiers.md must mention Opus"
# Review gates reference the tier matrix AND still document the Opus conductor/adjudication
# (the honest invariant — NOT the old blanket "todos os subagentes em Opus")
grep -qi 'tier' "$BASE/references/review-gates.md" || fail "review-gates.md must reference the model tier"
grep -qi 'opus' "$BASE/references/review-gates.md" || fail "review-gates.md must document the Opus conductor/adjudication"
grep -qi 'security-review' "$BASE/references/review-gates.md" || fail "review-gates.md missing security sub-gate"
grep -qi 'MERGED' "$BASE/references/finalize.md" || fail "finalize.md must gate on MERGED state"
grep -qi 'pyproject\|package.json' "$BASE/references/pre-push-gate.md" || fail "pre-push-gate.md missing stack detection"
grep -qi 'main' "$BASE/references/setup-gate.md" || fail "setup-gate.md must require branch from main"
# Passo do ponytail por tier (opcional, fail-open) documentado na Fase 0
grep -qi 'ponytail' "$BASE/references/setup-gate.md" || fail "setup-gate.md must document the ponytail-by-tier step"
echo "PASS test_references"
