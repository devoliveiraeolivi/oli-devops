#!/usr/bin/env sh
# NOTE: no `set -e` — we deliberately capture non-zero exit codes (the guard returns 2 on block).
set -u
# SC2015: A && B || C aqui é intencional (pwd -W só existe no Git-Bash/Windows; fallback pwd).
# shellcheck disable=SC2015
HERE="$(cd "$(dirname "$0")" && pwd -W 2>/dev/null || pwd)"
GUARD="$HERE/../scripts/branch-state-guard.sh"
pass=0; fail=0
# run guard, capture rc; usage: rc=$(gate_rc <json> [env assignments...])
gate_rc() { json="$1"; shift; rc=0; printf '%s' "$json" | env "$@" "${HARNESS_TEST_SHELL:-sh}" "$GUARD" >/dev/null 2>&1 || rc=$?; echo "$rc"; }
# capture stderr (stdout discarded); usage: err=$(gate_err <json> [env...])
# SC2069: ordem intencional — captura stderr p/ asserts de mensagem, descarta stdout.
# shellcheck disable=SC2069
gate_err() { json="$1"; shift; printf '%s' "$json" | env "$@" "${HARNESS_TEST_SHELL:-sh}" "$GUARD" 2>&1 >/dev/null; }
check() { if [ "$1" = "$2" ]; then pass=$((pass+1)); else echo "FAIL: $3 (got rc=$1, want $2)" >&2; fail=$((fail+1)); fi; }
checkc() { if printf '%s' "$1" | grep -qi "$2"; then pass=$((pass+1)); else echo "FAIL: $3 (stderr lacked '$2')" >&2; fail=$((fail+1)); fi; }

# 1. Non-gated command → 0 (never touches git/gh)
check "$(gate_rc '{"tool_input":{"command":"git status"}}')" 0 "non-gated command passes"
# 2. Text mentioning push but not a push command → 0
check "$(gate_rc '{"tool_input":{"command":"echo lembrar de git push depois"}}')" 0 "echo mentioning push is not a push"
# 3a. Push on main → 0
check "$(gate_rc '{"tool_input":{"command":"git push"}}' HARNESS_GUARD_BRANCH=main HARNESS_GUARD_GH_CMD='echo MERGED')" 0 "push on main passes"
# 3b. Commit on main → 0
check "$(gate_rc '{"tool_input":{"command":"git commit -m x"}}' HARNESS_GUARD_BRANCH=main HARNESS_GUARD_GH_CMD='echo MERGED')" 0 "commit on main passes"
# 4. Push on feature branch with MERGED PR → 2
check "$(gate_rc '{"tool_input":{"command":"git push"}}' HARNESS_GUARD_BRANCH=feat/x HARNESS_GUARD_GH_CMD='echo MERGED')" 2 "push on MERGED branch blocks"
# 5. Commit on feature branch with MERGED PR → 2
check "$(gate_rc '{"tool_input":{"command":"git commit -m x"}}' HARNESS_GUARD_BRANCH=feat/x HARNESS_GUARD_GH_CMD='echo MERGED')" 2 "commit on MERGED branch blocks"
# 6. Push on feature branch with OPEN PR → 0
check "$(gate_rc '{"tool_input":{"command":"git push"}}' HARNESS_GUARD_BRANCH=feat/x HARNESS_GUARD_GH_CMD='echo OPEN')" 0 "push on OPEN branch passes"
# 7. gh fails (rc!=0, empty stdout) → 0 (fail-open)
check "$(gate_rc '{"tool_input":{"command":"git push"}}' HARNESS_GUARD_BRANCH=feat/x HARNESS_GUARD_GH_CMD=false)" 0 "gh failure is fail-open"
# 8. Env-prefixed push on MERGED branch → 2 (env-prefix strip regression)
check "$(gate_rc '{"tool_input":{"command":"FOO=bar git push"}}' HARNESS_GUARD_BRANCH=feat/x HARNESS_GUARD_GH_CMD='echo MERGED')" 2 "env-prefixed push is gated"
# 9. Gate marker does NOT bypass anti-orphan → 2
check "$(gate_rc '{"tool_input":{"command":"HARNESS_GATE_OK=1 git push"}}' HARNESS_GUARD_BRANCH=feat/x HARNESS_GUARD_GH_CMD='echo MERGED')" 2 "HARNESS_GATE_OK marker does not bypass guard"
# 10. CLOSED (not merged) PR → 0
check "$(gate_rc '{"tool_input":{"command":"git push"}}' HARNESS_GUARD_BRANCH=feat/x HARNESS_GUARD_GH_CMD='echo CLOSED')" 0 "CLOSED PR passes"
# 11a. False positive: git commit-tree on MERGED branch → 0 (not the git commit token)
check "$(gate_rc '{"tool_input":{"command":"git commit-tree HEAD"}}' HARNESS_GUARD_BRANCH=feat/x HARNESS_GUARD_GH_CMD='echo MERGED')" 0 "git commit-tree is not gated"
# 11b. False positive: git pushy on MERGED branch → 0
check "$(gate_rc '{"tool_input":{"command":"git pushy"}}' HARNESS_GUARD_BRANCH=feat/x HARNESS_GUARD_GH_CMD='echo MERGED')" 0 "git pushy is not gated"
# 12. Newer OPEN PR over older MERGED (seam echoes newest = OPEN) → 0
check "$(gate_rc '{"tool_input":{"command":"git push"}}' HARNESS_GUARD_BRANCH=feat/x HARNESS_GUARD_GH_CMD='echo OPEN')" 0 "newest-PR-wins: OPEN over MERGED passes"
# 13. Empty branch / detached HEAD → 0
check "$(gate_rc '{"tool_input":{"command":"git push"}}' HARNESS_GUARD_BRANCH= HARNESS_GUARD_GH_CMD='echo MERGED')" 0 "empty branch passes"
# 14. Kill switch → 0 even on MERGED
check "$(gate_rc '{"tool_input":{"command":"git push"}}' HARNESS_GUARD_DISABLE=1 HARNESS_GUARD_BRANCH=feat/x HARNESS_GUARD_GH_CMD='echo MERGED')" 0 "kill switch disables guard"
# 15. Worktree warning: main checkout + feature branch → 0 + stderr warning
check "$(gate_rc '{"tool_input":{"command":"git push"}}' HARNESS_GUARD_IN_WORKTREE=0 HARNESS_GUARD_BRANCH=feat/x HARNESS_GUARD_GH_CMD='echo OPEN')" 0 "worktree warning does not block"
checkc "$(gate_err '{"tool_input":{"command":"git push"}}' HARNESS_GUARD_IN_WORKTREE=0 HARNESS_GUARD_BRANCH=feat/x HARNESS_GUARD_GH_CMD='echo OPEN')" "worktree" "worktree warning emitted on main checkout"
# 16. Compound command: `cd <dir> && git push` on MERGED branch → 2 (segment matching)
check "$(gate_rc '{"tool_input":{"command":"cd /repo && git push"}}' HARNESS_GUARD_BRANCH=feat/x HARNESS_GUARD_GH_CMD='echo MERGED')" 2 "cd && git push is gated"
# 17. Compound command: `cd <dir> && git commit -m x` on MERGED branch → 2
check "$(gate_rc '{"tool_input":{"command":"cd /repo && git commit -m x"}}' HARNESS_GUARD_BRANCH=feat/x HARNESS_GUARD_GH_CMD='echo MERGED')" 2 "cd && git commit is gated"
# 18. Compound command with ; separator: `git add . ; git commit -m x` on MERGED → 2
check "$(gate_rc '{"tool_input":{"command":"git add . ; git commit -m x"}}' HARNESS_GUARD_BRANCH=feat/x HARNESS_GUARD_GH_CMD='echo MERGED')" 2 "git add ; git commit is gated"
# 19. No false positive: leading `echo` mentioning push, no separator → 0
check "$(gate_rc '{"tool_input":{"command":"echo git push"}}' HARNESS_GUARD_BRANCH=feat/x HARNESS_GUARD_GH_CMD='echo MERGED')" 0 "leading echo of git push is not gated"
# 20. Compound command but push is on OPEN branch → 0 (gated then allowed by state)
check "$(gate_rc '{"tool_input":{"command":"cd /repo && git push"}}' HARNESS_GUARD_BRANCH=feat/x HARNESS_GUARD_GH_CMD='echo OPEN')" 0 "cd && git push on OPEN passes"

# 21-23. O repo checado é o do comando (cd / git -C), não o cwd do evento. Repo real:
#        checkout principal na main, worktree em feat/merged (PR "MERGED" via seam do gh).
REPO="$(mktemp -d)"
trap 'rm -rf "$REPO"' EXIT
git -C "$REPO" init -q -b main
git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
git -C "$REPO" worktree add -q -b feat/merged "$REPO/wt"
ev() { printf '{"tool_input":{"command":"%s"},"cwd":"%s"}' "$1" "$2"; }
check "$(gate_rc "$(ev "cd $REPO/wt && git push" "$REPO")" HARNESS_GUARD_GH_CMD='echo MERGED')" 2 "cd into merged worktree && git push blocks"
check "$(gate_rc "$(ev "git -C $REPO/wt push" "$REPO")" HARNESS_GUARD_GH_CMD='echo MERGED')" 2 "git -C merged worktree push blocks"
check "$(gate_rc "$(ev "cd $REPO && git push" "$REPO/wt")" HARNESS_GUARD_GH_CMD='echo MERGED')" 0 "cd to main checkout && git push passes"

# 24. Sem seam: checkout principal numa feature branch avisa (não bloqueia); worktree não avisa.
git -C "$REPO" checkout -q -b feat/main-checkout
checkc "$(gate_err "$(ev "git -C $REPO push" "$REPO/wt")" HARNESS_GUARD_GH_CMD='echo OPEN')" "worktree" "main checkout on feature branch warns"
wt_err="$(gate_err "$(ev "git -C $REPO/wt push" "$REPO")" HARNESS_GUARD_GH_CMD='echo OPEN')"
if printf '%s' "$wt_err" | grep -qi 'worktree'; then echo "FAIL: linked worktree must not warn" >&2; fail=$((fail+1)); else pass=$((pass+1)); fi

# 25-28. A branch checada é a que o push envia, não a do checkout.
git -C "$REPO" checkout -q main
git -C "$REPO" branch feat/old
check "$(gate_rc "$(ev "git -C $REPO push origin feat/old" "$REPO")" HARNESS_GUARD_GH_CMD='echo MERGED')" 2 "push of a merged branch from main blocks"
check "$(gate_rc "$(ev "git -C $REPO push origin main" "$REPO")" HARNESS_GUARD_GH_CMD='echo MERGED')" 0 "push of main passes"
check "$(gate_rc "$(ev "git -C $REPO push origin --delete feat/old" "$REPO")" HARNESS_GUARD_GH_CMD='echo MERGED')" 0 "deleting a merged remote branch passes"
git -C "$REPO" tag v1
check "$(gate_rc "$(ev "git -C $REPO push origin v1" "$REPO")" HARNESS_GUARD_GH_CMD='echo MERGED')" 0 "tag push is not a branch"

# 29-31. Formas do dia a dia: redirecionamento e commit+push contam; troca de branch antes libera.
check "$(gate_rc "$(ev "git push 2>&1 | tail -3" "$REPO/wt")" HARNESS_GUARD_GH_CMD='echo MERGED')" 2 "redirected push from merged worktree blocks"
check "$(gate_rc "$(ev "git commit -am x && git push" "$REPO/wt")" HARNESS_GUARD_GH_CMD='echo MERGED')" 2 "commit && push on merged branch blocks"
check "$(gate_rc "$(ev "git switch -c feat/next main && git commit -m x" "$REPO/wt")" HARNESS_GUARD_GH_CMD='echo MERGED')" 0 "switching branch first is not blocked"

echo "branch_state_guard: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
