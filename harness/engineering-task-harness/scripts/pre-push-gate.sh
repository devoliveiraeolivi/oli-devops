#!/usr/bin/env sh
# Pre-push gate (backstop). Reads the PreToolUse event JSON on stdin.
# Exit 0 = allow (not a push / gate marker / unknown stack / tool missing / cannot tell what the
#          push sends / checks pass). Exit 2 = block (a check that ran failed).
# The hook runs BEFORE the command: it sees the repo as it is now. When the push may send
# something other than the current HEAD, it lets it through with a note — CI validates the SHA.
set -u
set -f  # refs never glob

PY="$(command -v python 2>/dev/null || command -v python3 2>/dev/null || echo python)"
HERE="$(cd "$(dirname "$0")" && pwd)"

event="$(cat 2>/dev/null || true)"

# Cheap prefilter: no "push" in the raw event → nothing to gate (skips python on most calls).
case "$event" in
  *push*) : ;;
  *) exit 0 ;;
esac

# Every `git push` of the command as "<dir>\t<marker>\t<switched>\t<refs>" (see git_targets.py).
targets="$(printf '%s' "$event" | "$PY" "$HERE/git_targets.py" push 2>/dev/null)"
[ -n "$targets" ] || exit 0

run() { echo ">> $1" >&2; sh -c "$1"; }

# The checks run on the working tree: they vouch for the push only when it sends the
# checked-out HEAD. $1 = repo dir, $2 = refs.
sends_head() {
  git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0  # não é repo git
  head="$(git -C "$1" rev-parse HEAD 2>/dev/null || true)"
  for ref in $2; do
    case "$ref" in
      :*) sha="" ;;   # :multi / :unknown
      *) sha="$(git -C "$1" rev-parse --verify --quiet "$ref^{commit}" 2>/dev/null || true)" ;;
    esac
    if [ "$sha" != "$head" ]; then
      echo "harness gate: o push envia '$ref', não o HEAD de $1 — não validado aqui (o CI valida)." >&2
      return 1
    fi
  done
  return 0
}

# $1 = target dir, $2 = switched, $3 = refs. Returns 2 to block.
gate() {
  [ -n "$3" ] || return 0   # push que só apaga: nada a validar
  if [ "$2" = "1" ]; then
    echo "harness gate: o comando troca de branch antes do push — não validado aqui (o CI valida)." >&2
    return 0
  fi
  if [ -n "${HARNESS_GATE_DIR:-}" ]; then
    dir="$HARNESS_GATE_DIR"
  else
    dir="$(git -C "$1" rev-parse --show-toplevel 2>/dev/null || echo "$1")"
  fi

  # Gate próprio do repo (espelho do CI, fonte única) vence — a menos que um
  # override *_CMDS esteja setado (escape hatch + determinismo de teste).
  if [ -z "${HARNESS_PYTHON_CMDS:-}${HARNESS_NODE_CMDS:-}" ] && [ -x "$dir/scripts/check.sh" ]; then
    cmds="scripts/check.sh --fast"
    failed="scripts/check.sh --fast falhou"
  elif [ -f "$dir/pyproject.toml" ]; then
    if ! command -v uv >/dev/null 2>&1 && [ -z "${HARNESS_PYTHON_CMDS:-}" ]; then
      echo "harness gate: 'uv' não está no PATH — pulando checagem python em $dir." >&2
      return 0
    fi
    if [ -n "${HARNESS_PYTHON_CMDS:-}" ]; then
      cmds="$HARNESS_PYTHON_CMDS"
    else
      # mypy baseline-aware: com baseline, só falha em erro NOVO (igual ao CI).
      if [ -f "$dir/.mypy-baseline.txt" ] && (cd "$dir" && uv run mypy-baseline --version >/dev/null 2>&1); then
        mypy_cmd="uv run mypy src/ | uv run mypy-baseline filter --baseline-path .mypy-baseline.txt --allow-unsynced"
      else
        mypy_cmd="uv run mypy src/"
      fi
      # Sem black (legado → ruff format) e sem pytest (já roda na verificação do repo antes do PR).
      cmds="uv run ruff check src/ && uv run ruff format --check src/ tests/ && $mypy_cmd"
    fi
    failed="pre-push gate (python) falhou"
  elif [ -f "$dir/package.json" ]; then
    if ! command -v npm >/dev/null 2>&1 && [ -z "${HARNESS_NODE_CMDS:-}" ]; then
      echo "harness gate: 'npm' não está no PATH — pulando checagem node em $dir." >&2
      return 0
    fi
    if [ -n "${HARNESS_NODE_CMDS:-}" ]; then
      cmds="$HARNESS_NODE_CMDS"
    else
      # Only run scripts that actually exist (missing script = skip, not fail).
      cmds="true"
      for s in lint test build; do
        if (cd "$dir" && npm run 2>/dev/null) | grep -qE "^[[:space:]]*$s\$"; then
          cmds="$cmds && npm run -s $s"
        fi
      done
    fi
    failed="pre-push gate (node) falhou"
  else
    echo "harness pre-push gate: stack não reconhecida em $dir — push liberado sem checagem." >&2
    return 0
  fi

  sends_head "$dir" "$3" || return 0
  if ! (cd "$dir" && run "$cmds"); then
    echo "BLOQUEADO: $failed em $dir. Corrija antes de dar push." >&2
    return 2
  fi
  return 0
}

tab="$(printf '\t')"
rc=0
while IFS="$tab" read -r target_dir marker switched refs; do
  # Gate marker: `HARNESS_GATE_OK=1 git push` only after the repo check ran on this HEAD in
  # this session. It counts only as a leading assignment of that push command.
  [ "$marker" = "1" ] && continue
  gate "$target_dir" "$switched" "$refs" || rc=2
done <<TARGETS
$targets
TARGETS
exit "$rc"
