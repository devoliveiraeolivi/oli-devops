#!/usr/bin/env sh
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
SK="$HERE/../skills/dev-cycle/SKILL.md"
CMD="$HERE/../commands/oli-dev.md"
fail() { echo "FAIL: $1" >&2; exit 1; }

[ -f "$SK" ] || fail "SKILL.md missing"
[ -f "$CMD" ] || fail "oli-dev.md command missing"
# YAML frontmatter with name + description
head -1 "$SK" | grep -q '^---$' || fail "SKILL.md missing frontmatter"
grep -q '^name: dev-cycle$' "$SK" || fail "skill name not dev-cycle"
grep -q '^description:' "$SK" || fail "skill missing description"
# 4 fixed body sections
for s in "## When to Use" "## Prerequisites" "## Workflow" "## Verification"; do
  grep -qF "$s" "$SK" || fail "missing section: $s"
done
# References wired (progressive disclosure)
for r in setup-gate review-gates pre-push-gate finalize model-tiers; do
  grep -qF "references/$r.md" "$SK" || fail "SKILL.md does not link references/$r.md"
done
# The 8 phases are listed
for p in "Fase 0" "Fase 1" "Fase 2" "Fase 3" "Fase 4" "Fase 5" "Fase 6" "Fase 7" "Fase 8"; do
  grep -qF "$p" "$SK" || fail "missing $p in workflow"
done
# Command declares finalize mode + the light/full tier tokens
grep -qF "finalize" "$CMD" || fail "command missing finalize mode"
for t in light full; do
  grep -qiF "$t" "$CMD" || fail "command missing tier token: $t"
done
echo "PASS test_skill_structure"
