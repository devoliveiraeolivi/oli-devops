#!/usr/bin/env sh
# NOTE: no `set -e` — we deliberately capture non-zero exit codes (the guard returns 2 on block).
set -u
HERE="$(cd "$(dirname "$0")" && pwd -W 2>/dev/null || pwd)"
GUARD="$HERE/../hooks/branch-state-guard.sh"
pass=0; fail=0
# run guard, capture rc; usage: rc=$(gate_rc <json> [env assignments...])
gate_rc() { json="$1"; shift; rc=0; printf '%s' "$json" | env "$@" "${OLI_DEV_TEST_SHELL:-sh}" "$GUARD" >/dev/null 2>&1 || rc=$?; echo "$rc"; }
# capture stderr (stdout discarded); usage: err=$(gate_err <json> [env...])
gate_err() { json="$1"; shift; printf '%s' "$json" | env "$@" "${OLI_DEV_TEST_SHELL:-sh}" "$GUARD" 2>&1 >/dev/null; }
check() { if [ "$1" = "$2" ]; then pass=$((pass+1)); else echo "FAIL: $3 (got rc=$1, want $2)" >&2; fail=$((fail+1)); fi; }
checkc() { if printf '%s' "$1" | grep -qi "$2"; then pass=$((pass+1)); else echo "FAIL: $3 (stderr lacked '$2')" >&2; fail=$((fail+1)); fi; }

# 1. Non-gated command → 0 (never touches git/gh)
check "$(gate_rc '{"tool_input":{"command":"git status"}}')" 0 "non-gated command passes"
# 2. Text mentioning push but not a push command → 0
check "$(gate_rc '{"tool_input":{"command":"echo lembrar de git push depois"}}')" 0 "echo mentioning push is not a push"
# 3a. Push on main → 0
check "$(gate_rc '{"tool_input":{"command":"git push"}}' OLI_DEV_GUARD_BRANCH=main OLI_DEV_GUARD_GH_CMD='echo MERGED')" 0 "push on main passes"
# 3b. Commit on main → 0
check "$(gate_rc '{"tool_input":{"command":"git commit -m x"}}' OLI_DEV_GUARD_BRANCH=main OLI_DEV_GUARD_GH_CMD='echo MERGED')" 0 "commit on main passes"
# 4. Push on feature branch with MERGED PR → 2
check "$(gate_rc '{"tool_input":{"command":"git push"}}' OLI_DEV_GUARD_BRANCH=feat/x OLI_DEV_GUARD_GH_CMD='echo MERGED')" 2 "push on MERGED branch blocks"
# 5. Commit on feature branch with MERGED PR → 2
check "$(gate_rc '{"tool_input":{"command":"git commit -m x"}}' OLI_DEV_GUARD_BRANCH=feat/x OLI_DEV_GUARD_GH_CMD='echo MERGED')" 2 "commit on MERGED branch blocks"
# 6. Push on feature branch with OPEN PR → 0
check "$(gate_rc '{"tool_input":{"command":"git push"}}' OLI_DEV_GUARD_BRANCH=feat/x OLI_DEV_GUARD_GH_CMD='echo OPEN')" 0 "push on OPEN branch passes"
# 7. gh fails (rc!=0, empty stdout) → 0 (fail-open)
check "$(gate_rc '{"tool_input":{"command":"git push"}}' OLI_DEV_GUARD_BRANCH=feat/x OLI_DEV_GUARD_GH_CMD=false)" 0 "gh failure is fail-open"
# 8. Env-prefixed push on MERGED branch → 2 (env-prefix strip regression)
check "$(gate_rc '{"tool_input":{"command":"FOO=bar git push"}}' OLI_DEV_GUARD_BRANCH=feat/x OLI_DEV_GUARD_GH_CMD='echo MERGED')" 2 "env-prefixed push is gated"
# 9. In-cycle marker does NOT bypass anti-orphan → 2
check "$(gate_rc '{"tool_input":{"command":"OLI_DEV_GATE_OK=1 git push"}}' OLI_DEV_GUARD_BRANCH=feat/x OLI_DEV_GUARD_GH_CMD='echo MERGED')" 2 "OLI_DEV_GATE_OK marker does not bypass guard"
# 10. CLOSED (not merged) PR → 0
check "$(gate_rc '{"tool_input":{"command":"git push"}}' OLI_DEV_GUARD_BRANCH=feat/x OLI_DEV_GUARD_GH_CMD='echo CLOSED')" 0 "CLOSED PR passes"
# 11a. False positive: git commit-tree on MERGED branch → 0 (not the git commit token)
check "$(gate_rc '{"tool_input":{"command":"git commit-tree HEAD"}}' OLI_DEV_GUARD_BRANCH=feat/x OLI_DEV_GUARD_GH_CMD='echo MERGED')" 0 "git commit-tree is not gated"
# 11b. False positive: git pushy on MERGED branch → 0
check "$(gate_rc '{"tool_input":{"command":"git pushy"}}' OLI_DEV_GUARD_BRANCH=feat/x OLI_DEV_GUARD_GH_CMD='echo MERGED')" 0 "git pushy is not gated"
# 12. Newer OPEN PR over older MERGED (seam echoes newest = OPEN) → 0
check "$(gate_rc '{"tool_input":{"command":"git push"}}' OLI_DEV_GUARD_BRANCH=feat/x OLI_DEV_GUARD_GH_CMD='echo OPEN')" 0 "newest-PR-wins: OPEN over MERGED passes"
# 13. Empty branch / detached HEAD → 0
check "$(gate_rc '{"tool_input":{"command":"git push"}}' OLI_DEV_GUARD_BRANCH= OLI_DEV_GUARD_GH_CMD='echo MERGED')" 0 "empty branch passes"
# 14. Kill switch → 0 even on MERGED
check "$(gate_rc '{"tool_input":{"command":"git push"}}' OLI_DEV_GUARD_DISABLE=1 OLI_DEV_GUARD_BRANCH=feat/x OLI_DEV_GUARD_GH_CMD='echo MERGED')" 0 "kill switch disables guard"
# 15. Worktree warning: main checkout + feature branch → 0 + stderr warning
check "$(gate_rc '{"tool_input":{"command":"git push"}}' OLI_DEV_GUARD_IN_WORKTREE=0 OLI_DEV_GUARD_BRANCH=feat/x OLI_DEV_GUARD_GH_CMD='echo OPEN')" 0 "worktree warning does not block"
checkc "$(gate_err '{"tool_input":{"command":"git push"}}' OLI_DEV_GUARD_IN_WORKTREE=0 OLI_DEV_GUARD_BRANCH=feat/x OLI_DEV_GUARD_GH_CMD='echo OPEN')" "worktree" "worktree warning emitted on main checkout"
# 16. Compound command: `cd <dir> && git push` on MERGED branch → 2 (segment matching)
check "$(gate_rc '{"tool_input":{"command":"cd /repo && git push"}}' OLI_DEV_GUARD_BRANCH=feat/x OLI_DEV_GUARD_GH_CMD='echo MERGED')" 2 "cd && git push is gated"
# 17. Compound command: `cd <dir> && git commit -m x` on MERGED branch → 2
check "$(gate_rc '{"tool_input":{"command":"cd /repo && git commit -m x"}}' OLI_DEV_GUARD_BRANCH=feat/x OLI_DEV_GUARD_GH_CMD='echo MERGED')" 2 "cd && git commit is gated"
# 18. Compound command with ; separator: `git add . ; git commit -m x` on MERGED → 2
check "$(gate_rc '{"tool_input":{"command":"git add . ; git commit -m x"}}' OLI_DEV_GUARD_BRANCH=feat/x OLI_DEV_GUARD_GH_CMD='echo MERGED')" 2 "git add ; git commit is gated"
# 19. No false positive: leading `echo` mentioning push, no separator → 0
check "$(gate_rc '{"tool_input":{"command":"echo git push"}}' OLI_DEV_GUARD_BRANCH=feat/x OLI_DEV_GUARD_GH_CMD='echo MERGED')" 0 "leading echo of git push is not gated"
# 20. Compound command but push is on OPEN branch → 0 (gated then allowed by state)
check "$(gate_rc '{"tool_input":{"command":"cd /repo && git push"}}' OLI_DEV_GUARD_BRANCH=feat/x OLI_DEV_GUARD_GH_CMD='echo OPEN')" 0 "cd && git push on OPEN passes"

echo "branch_state_guard: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
