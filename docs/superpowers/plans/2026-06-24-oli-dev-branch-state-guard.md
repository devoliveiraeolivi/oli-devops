# branch-state-guard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a deterministic `branch-state-guard.sh` hook that blocks `git push`/`git commit` on a feature branch whose PR is already MERGED (anti-órfão), plus a non-blocking worktree warning and a Fase 0 doc reinforcement.

**Architecture:** A second PreToolUse/`Bash` hook sibling to `pre-push-gate.sh`, in `plugins/oli-dev/hooks/`. It parses the event JSON on stdin (python, no `jq`), gates only commands whose leading token (after env-prefix strip) is `git push`/`git commit`, resolves the branch, and queries PR state via `gh pr view <branch> --json state -q .state`. Fail-open when `gh` can't answer. Fully driven by `OLI_DEV_GUARD_*` env seams for testing.

**Tech Stack:** POSIX `sh` (Git Bash on Windows), `python` for JSON parse, `gh` CLI, plugin shell-test harness (`tests/test_*.sh` auto-discovered by `run_all.sh`).

## Global Constraints

- POSIX `sh` only; runs under Git Bash on Windows. Use `command -v`, paths POSIX, **no `jq`**.
- Exit `0` = allow, exit `2` = block. Fail-open (`exit 0` + stderr) when `gh` is missing/unauthenticated/offline.
- Mirror `pre-push-gate.sh` conventions: stdin JSON, python parse, quote-aware env-prefix strip, event-`cwd` dir resolution.
- Test seams (independent of the `OLI_DEV_GATE_*` prefix): `OLI_DEV_GUARD_DIR`, `OLI_DEV_GUARD_BRANCH`, `OLI_DEV_GUARD_GH_CMD`, `OLI_DEV_GUARD_IN_WORKTREE`, `OLI_DEV_GUARD_DISABLE`.
- The in-cycle marker `OLI_DEV_GATE_OK=1` does **NOT** bypass this guard.
- `gh pr view <branch>` returns the **newest** PR's state ("newest-PR-wins" is intended).
- Comments/messages in português (project convention).

---

### Task 1: `branch-state-guard.sh` hook + its test

**Files:**
- Create: `plugins/oli-dev/hooks/branch-state-guard.sh`
- Test: `plugins/oli-dev/tests/test_branch_state_guard.sh`

**Interfaces:**
- Consumes: PreToolUse event JSON on stdin (`{"tool_input":{"command":...},"cwd":...}`); env seams listed in Global Constraints.
- Produces: a hook script invoked as `sh branch-state-guard.sh`; exit `0`/`2`. Task 2 wires it into `hooks.json`. The test file is auto-discovered by the existing `tests/run_all.sh` (globs `test_*.sh`) — no registration step needed.

- [ ] **Step 1: Write the failing test** — create `plugins/oli-dev/tests/test_branch_state_guard.sh`:

```sh
#!/usr/bin/env sh
# NOTE: no `set -e` — we deliberately capture non-zero exit codes (the guard returns 2 on block).
set -u
HERE="$(cd "$(dirname "$0")" && pwd -W 2>/dev/null || pwd)"
GUARD="$HERE/../hooks/branch-state-guard.sh"
pass=0; fail=0
# run guard, capture rc; usage: rc=$(gate_rc <json> [env assignments...])
gate_rc() { json="$1"; shift; rc=0; printf '%s' "$json" | env "$@" sh "$GUARD" >/dev/null 2>&1 || rc=$?; echo "$rc"; }
# capture stderr (stdout discarded); usage: err=$(gate_err <json> [env...])
gate_err() { json="$1"; shift; printf '%s' "$json" | env "$@" sh "$GUARD" 2>&1 >/dev/null; }
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

echo "branch_state_guard: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
```

(The stray `MERGED=` placeholder line is illustrative — delete it; each test sets `OLI_DEV_GUARD_GH_CMD` inline.)

- [ ] **Step 2: Run test to verify it fails**

Run: `cd plugins/oli-dev && sh tests/test_branch_state_guard.sh`
Expected: FAIL — the guard script does not exist yet (`sh: .../branch-state-guard.sh: No such file or directory`), so checks for `rc=0` cases may coincidentally pass but the `rc=2` block cases (4,5,8,9) will report `FAIL ... want 2` and the suite exits non-zero.

- [ ] **Step 3: Write minimal implementation** — create `plugins/oli-dev/hooks/branch-state-guard.sh`:

```sh
#!/usr/bin/env sh
# Branch-state guard (anti-órfão). Lê o evento PreToolUse (JSON) no stdin.
# Exit 0 = libera. Exit 2 = bloqueia (push/commit numa branch cuja PR está MERGED).
# Irmão do pre-push-gate.sh; seams OLI_DEV_GUARD_* independentes do OLI_DEV_GATE_*.
set -u

# Kill switch.
[ "${OLI_DEV_GUARD_DISABLE:-}" = "1" ] && exit 0

PY="$(command -v python 2>/dev/null || command -v python3 2>/dev/null || echo python)"

event="$(cat 2>/dev/null || true)"

# Extrai tool_input.command e cwd do JSON via python (sem jq).
cmd="$(printf '%s' "$event" | "$PY" -c 'import json,sys
try:
    e=json.load(sys.stdin)
except Exception:
    print(""); sys.exit(0)
print((e.get("tool_input") or {}).get("command","") or "")' 2>/dev/null || true)"
evcwd="$(printf '%s' "$event" | "$PY" -c 'import json,sys
try:
    e=json.load(sys.stdin)
except Exception:
    print(""); sys.exit(0)
print(e.get("cwd","") or "")' 2>/dev/null || true)"

# Strip de env-prefixes VAR=val (quote-aware), depois exige git push/commit como token líder.
core="$(printf '%s' "$cmd" | sed -E "s/^([A-Za-z_][A-Za-z0-9_]*=('[^']*'|\"[^\"]*\"|[^ ]*) +)+//")"
case "$core" in
  'git push'|'git push '*|'git commit'|'git commit '*) : ;;  # gated → continua
  *) exit 0 ;;                                                # não é push/commit → libera
esac

# Resolve o dir do repo a partir do cwd do EVENTO (correto dentro de worktrees).
if [ -n "${OLI_DEV_GUARD_DIR:-}" ]; then
  dir="$OLI_DEV_GUARD_DIR"
else
  base="${evcwd:-$(pwd)}"
  dir="$(git -C "$base" rev-parse --show-toplevel 2>/dev/null || echo "$base")"
fi

# Branch atual (seam +x para distinguir "setado vazio" de "não setado").
if [ -n "${OLI_DEV_GUARD_BRANCH+x}" ]; then
  branch="$OLI_DEV_GUARD_BRANCH"
else
  branch="$(git -C "$dir" branch --show-current 2>/dev/null || true)"
fi
case "$branch" in
  ''|main|master) exit 0 ;;   # main/sem-branch não gera órfão de feature
esac

# Aviso de worktree (não-bloqueio): checkout principal numa feature branch.
if [ -n "${OLI_DEV_GUARD_IN_WORKTREE:-}" ]; then
  in_wt="$OLI_DEV_GUARD_IN_WORKTREE"
else
  gd="$(git -C "$dir" rev-parse --git-dir 2>/dev/null || echo __a)"
  gcd="$(git -C "$dir" rev-parse --git-common-dir 2>/dev/null || echo __b)"
  gd="$(cd "$gd" 2>/dev/null && pwd -P || echo "$gd")"
  gcd="$(cd "$gcd" 2>/dev/null && pwd -P || echo "$gcd")"
  if [ "$gd" = "$gcd" ]; then in_wt=0; else in_wt=1; fi
fi
if [ "$in_wt" = "0" ]; then
  echo "oli-dev guard: trabalhando no checkout principal numa feature branch ('$branch') — considere um worktree (.worktrees/<feat>)." >&2
fi

# Anti-órfão: estado da PR como string nua.
if [ -n "${OLI_DEV_GUARD_GH_CMD+x}" ]; then
  state="$(sh -c "$OLI_DEV_GUARD_GH_CMD" 2>/dev/null || true)"
else
  if ! command -v gh >/dev/null 2>&1; then
    echo "oli-dev guard: 'gh' ausente — anti-órfão não checado (fail-open)." >&2
    exit 0
  fi
  state="$(gh pr view "$branch" --json state -q .state 2>/dev/null || true)"
fi
state="$(printf '%s' "$state" | tr -d '[:space:]')"

if [ -z "$state" ]; then
  echo "oli-dev guard: estado da PR indisponível (gh sem resposta) — anti-órfão não checado (fail-open)." >&2
  exit 0
fi

if [ "$state" = "MERGED" ]; then
  echo "BLOQUEADO: a PR da branch '$branch' já está MERGED — commits/pushes aqui ficam órfãos. Crie uma branch nova a partir da main." >&2
  exit 2
fi

exit 0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd plugins/oli-dev && sh tests/test_branch_state_guard.sh`
Expected: `branch_state_guard: 18 passed, 0 failed` (15 numbered cases; #3 and #11 each have two `check` calls, and #15 has one `check` + one `checkc` → 18 assertions total).

- [ ] **Step 5: Run the full suite to confirm auto-discovery + no regression**

Run: `cd plugins/oli-dev && sh tests/run_all.sh`
Expected: ends with `ALL GREEN`; output includes the `test_branch_state_guard.sh` block.

- [ ] **Step 6: Commit**

```bash
git add plugins/oli-dev/hooks/branch-state-guard.sh plugins/oli-dev/tests/test_branch_state_guard.sh
git commit -m "feat(oli-dev): branch-state-guard hook (anti-orfao em branch MERGED)"
```

---

### Task 2: Wire the hook into `hooks.json` + manifest test

**Files:**
- Modify: `plugins/oli-dev/hooks/hooks.json`
- Modify: `plugins/oli-dev/tests/test_manifests.sh`

**Interfaces:**
- Consumes: `branch-state-guard.sh` from Task 1.
- Produces: the guard registered as a second PreToolUse/`Bash` hook so Claude Code actually runs it; a manifest assertion that both hook scripts are referenced and exist.

- [ ] **Step 1: Write the failing test** — append to `plugins/oli-dev/tests/test_manifests.sh`, right before the final `echo "PASS test_manifests"` line:

```sh
# hooks.json: valid JSON + both PreToolUse/Bash hooks registered + their scripts exist
python - "$ROOT" <<'PY'
import json, os, sys
root = sys.argv[1]
hj = json.load(open(f"{root}/plugins/oli-dev/hooks/hooks.json"))
pre = hj["hooks"]["PreToolUse"]
bash = [g for g in pre if g.get("matcher") == "Bash"]
assert bash, "no Bash PreToolUse group"
cmds = [h.get("command","") for g in bash for h in g.get("hooks", [])]
for script in ("pre-push-gate.sh", "branch-state-guard.sh"):
    assert any(script in c for c in cmds), f"{script} not registered in hooks.json"
    assert os.path.exists(f"{root}/plugins/oli-dev/hooks/{script}"), f"{script} file missing"
print("OK hooks.json")
PY
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd plugins/oli-dev && sh tests/test_manifests.sh`
Expected: FAIL — `AssertionError: branch-state-guard.sh not registered in hooks.json` (the script exists from Task 1 but is not yet wired).

- [ ] **Step 3: Write minimal implementation** — replace the full contents of `plugins/oli-dev/hooks/hooks.json` with:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "sh \"${CLAUDE_PLUGIN_ROOT}/hooks/pre-push-gate.sh\"" },
          { "type": "command", "command": "sh \"${CLAUDE_PLUGIN_ROOT}/hooks/branch-state-guard.sh\"" }
        ]
      }
    ]
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd plugins/oli-dev && sh tests/test_manifests.sh`
Expected: prints `OK hooks.json` then `PASS test_manifests`.

- [ ] **Step 5: Run the full suite**

Run: `cd plugins/oli-dev && sh tests/run_all.sh`
Expected: `ALL GREEN`.

- [ ] **Step 6: Commit**

```bash
git add plugins/oli-dev/hooks/hooks.json plugins/oli-dev/tests/test_manifests.sh
git commit -m "feat(oli-dev): registra branch-state-guard no hooks.json + teste de manifesto"
```

---

### Task 3: Fase 0 doc reinforcement

**Files:**
- Modify: `plugins/oli-dev/skills/dev-cycle/references/setup-gate.md`
- Modify: `plugins/oli-dev/skills/dev-cycle/SKILL.md:26`

**Interfaces:**
- Consumes: nothing (documentation).
- Produces: Fase 0 resume/checkpoint guidance that refuses to resume on a MERGED branch or outside a worktree; a one-line principle pointer to the deterministic guard. Covered by the existing `tests/test_references.sh` (which checks the reference files exist/are non-trivial) and `tests/test_skill_structure.sh`.

- [ ] **Step 1: Add the resume guard to `setup-gate.md`** — replace the existing item 4:

```markdown
4. **Resume/checkpoint.** Detecte artefatos: spec+plano → retome Fase 4; só spec → Fase 2/3;
   nada → Fase 1. Anuncie de onde retoma e confirme antes de pular fases.
```

with:

```markdown
4. **Resume/checkpoint.** Detecte artefatos: spec+plano → retome Fase 4; só spec → Fase 2/3;
   nada → Fase 1. Anuncie de onde retoma e confirme antes de pular fases.
5. **Guard de branch ao retomar.** Antes de retomar trabalho numa branch existente, cheque:
   (a) estamos num **worktree linkado** (`git rev-parse --git-dir` ≠ `--git-common-dir`); e
   (b) a PR da branch **não** está MERGED (`gh pr view <branch> --json state`). Se a branch já
   está MERGED → **barre**: commits aqui viram órfãos (aconteceu na PR #4 → recovery na #5);
   crie uma branch nova da `main`. Se estamos no checkout principal (sem worktree) → volte para
   a `main` e crie o worktree. A enforcement determinística disto vive no hook
   `hooks/branch-state-guard.sh`; este passo é a orientação correspondente.
```

- [ ] **Step 2: Add the principle pointer to `SKILL.md`** — replace line 26:

```markdown
3. **Nunca deletar branch** sem `gh pr view <n> --json state` == `MERGED`.
```

with:

```markdown
3. **Nunca deletar branch** — nem continuar empurrando nela — sem `gh pr view <n> --json state`.
   Se a PR está `MERGED`, commits/pushes na branch viram órfãos; o hook `branch-state-guard.sh`
   bloqueia isso de forma determinística (push/commit), e a Fase 0 recusa retomar numa branch mergeada.
```

- [ ] **Step 3: Run the docs/structure tests**

Run: `cd plugins/oli-dev && sh tests/test_references.sh && sh tests/test_skill_structure.sh`
Expected: `PASS test_references` and `PASS test_skill_structure`.

- [ ] **Step 4: Run the full suite**

Run: `cd plugins/oli-dev && sh tests/run_all.sh`
Expected: `ALL GREEN`.

- [ ] **Step 5: Commit**

```bash
git add plugins/oli-dev/skills/dev-cycle/references/setup-gate.md plugins/oli-dev/skills/dev-cycle/SKILL.md
git commit -m "docs(oli-dev): Fase 0 recusa retomar em branch MERGED/sem-worktree + principio do guard"
```

---

## Notes for the implementer

- The three tasks are **serial** (Task 2 needs Task 1's script; Task 3 is independent but small). Run them in order.
- Do not pin a plugin `version` (the manifest test forbids it — stale-cache trap).
- After all tasks: `sh plugins/oli-dev/tests/run_all.sh` must print `ALL GREEN`.
