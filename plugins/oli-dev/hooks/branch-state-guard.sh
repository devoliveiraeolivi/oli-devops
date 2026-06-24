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

# Detecta `git push`/`git commit` como comando — inclusive em compostos (`cd x && git push`,
# `git add . ; git commit`). Quebra por separadores de comando (&& || ; |, newline) e, em cada
# segmento, tira espaço à esquerda + env-prefixes VAR=val (quote-aware) antes de casar o token líder.
# Limitação conhecida: um `git push`/`git commit` que comece um segmento DENTRO de aspas
# (ex: `echo "... && git push x"`) pode dar falso-positivo — raro, e só bloqueia em branch MERGED.
gated="$(printf '%s\n' "$cmd" | sed -E 's/&&/\n/g; s/\|\|/\n/g; s/;/\n/g; s/\|/\n/g' | while IFS= read -r seg; do
  seg="$(printf '%s' "$seg" | sed -E "s/^[[:space:]]+//; s/^([A-Za-z_][A-Za-z0-9_]*=('[^']*'|\"[^\"]*\"|[^ ]*) +)+//")"
  case "$seg" in
    'git push'|'git push '*|'git commit'|'git commit '*) echo yes ;;
  esac
done)"
case "$gated" in
  *yes*) : ;;       # é push/commit (talvez em comando composto) → continua
  *) exit 0 ;;      # não é push/commit → libera
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
