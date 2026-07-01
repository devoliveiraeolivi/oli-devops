#!/usr/bin/env sh
# Pre-push gate (backstop). Reads the PreToolUse event JSON on stdin.
# Exit 0 = allow (not a push / in-cycle / unknown stack / tool missing / checks pass).
# Exit 2 = block (a check that ran returned non-zero).
set -u

PY="$(command -v python 2>/dev/null || command -v python3 2>/dev/null || echo python)"

event="$(cat 2>/dev/null || true)"

# Extract tool_input.command and cwd from the event JSON via python (no jq; avoids raw-JSON match).
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

# Strip leading `VAR=val ` env-prefixes (quote-aware: handles FOO='a b' and FOO="a b"),
# then require the command to START with `git push`.
core="$(printf '%s' "$cmd" | sed -E "s/^([A-Za-z_][A-Za-z0-9_]*=('[^']*'|\"[^\"]*\"|[^ ]*) +)+//")"
# NOTE: compound commands where `git push` is NOT the leading token after env-prefix stripping
# (e.g. `cd repo && git push`) are intentionally NOT gated here — this is a backstop.
# The in-cycle Fase 7 push is always a bare `OLI_DEV_GATE_OK=1 git push`.
case "$core" in
  'git push'|'git push '*) : ;;   # it's a push → continue
  *) exit 0 ;;                     # not a push → allow
esac

# In-cycle marker: Fase 7 pushes with `OLI_DEV_GATE_OK=1 git push` (gate already ran in Fase 6).
# Anchored to a LEADING env-prefix so a stray branch name like `feat-OLI_DEV_GATE_OK=1` can't bypass.
case "$cmd" in
  OLI_DEV_GATE_OK=1\ *) exit 0 ;;
esac

# Resolve the repo dir from the EVENT cwd (correct inside worktrees), not CLAUDE_PROJECT_DIR.
if [ -n "${OLI_DEV_GATE_DIR:-}" ]; then
  dir="$OLI_DEV_GATE_DIR"
else
  base="${evcwd:-$(pwd)}"
  dir="$(git -C "$base" rev-parse --show-toplevel 2>/dev/null || echo "$base")"
fi

run() { echo ">> $1" >&2; sh -c "$1"; }

# Gate próprio do repo (espelho do CI, fonte única) vence — a menos que um
# override *_CMDS esteja setado (escape hatch + determinismo de teste).
if [ -z "${OLI_DEV_PYTHON_CMDS:-}${OLI_DEV_NODE_CMDS:-}" ] && [ -x "$dir/scripts/check.sh" ]; then
  cd "$dir" || exit 0
  if ! run "scripts/check.sh --fast"; then
    echo "BLOQUEADO: scripts/check.sh --fast falhou em $dir. Corrija antes de dar push." >&2
    exit 2
  fi
  exit 0
fi

if [ -f "$dir/pyproject.toml" ]; then
  if ! command -v uv >/dev/null 2>&1 && [ -z "${OLI_DEV_PYTHON_CMDS:-}" ]; then
    echo "oli-dev gate: 'uv' não está no PATH — pulando checagem python em $dir." >&2; exit 0
  fi
  cd "$dir" || exit 0
  if [ -n "${OLI_DEV_PYTHON_CMDS:-}" ]; then
    cmds="$OLI_DEV_PYTHON_CMDS"
  else
    # mypy baseline-aware: com baseline, só falha em erro NOVO (igual ao CI).
    if [ -f ".mypy-baseline.txt" ] && uv run mypy-baseline --version >/dev/null 2>&1; then
      mypy_cmd="uv run mypy src/ | uv run mypy-baseline filter --baseline-path .mypy-baseline.txt --allow-unsynced"
    else
      mypy_cmd="uv run mypy src/"
    fi
    # Sem black (legado → ruff format) e sem pytest (já roda no verify da Fase 5).
    cmds="uv run ruff check src/ && uv run ruff format --check src/ tests/ && $mypy_cmd"
  fi
  if ! run "$cmds"; then
    echo "BLOQUEADO: pre-push gate (python) falhou em $dir. Corrija antes de dar push." >&2
    exit 2
  fi
  exit 0
fi

if [ -f "$dir/package.json" ]; then
  if ! command -v npm >/dev/null 2>&1 && [ -z "${OLI_DEV_NODE_CMDS:-}" ]; then
    echo "oli-dev gate: 'npm' não está no PATH — pulando checagem node em $dir." >&2; exit 0
  fi
  cd "$dir" || exit 0
  if [ -n "${OLI_DEV_NODE_CMDS:-}" ]; then
    cmds="$OLI_DEV_NODE_CMDS"
  else
    # Only run scripts that actually exist (missing script = skip, not fail).
    cmds="true"
    for s in lint test build; do
      if npm run 2>/dev/null | grep -qE "^[[:space:]]*$s\$"; then
        cmds="$cmds && npm run -s $s"
      fi
    done
  fi
  if ! run "$cmds"; then
    echo "BLOQUEADO: pre-push gate (node) falhou em $dir. Corrija antes de dar push." >&2
    exit 2
  fi
  exit 0
fi

echo "oli-dev pre-push gate: stack não reconhecida em $dir — push liberado sem checagem." >&2
exit 0
