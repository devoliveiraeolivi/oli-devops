#!/usr/bin/env sh
# Branch-state guard (anti-órfão). Lê o evento PreToolUse (JSON) no stdin.
# Exit 0 = libera. Exit 2 = bloqueia (push/commit de uma branch cuja PR está MERGED).
# Irmão do pre-push-gate.sh; seams HARNESS_GUARD_* independentes do HARNESS_GATE_*.
set -u
set -f  # refs nunca viram glob

# Kill switch.
[ "${HARNESS_GUARD_DISABLE:-}" = "1" ] && exit 0

PY="$(command -v python 2>/dev/null || command -v python3 2>/dev/null || echo python)"
HERE="$(cd "$(dirname "$0")" && pwd)"

event="$(cat 2>/dev/null || true)"

# Pré-filtro barato: sem "push"/"commit" no evento cru → libera (não abre python à toa).
case "$event" in
  *push*|*commit*) : ;;
  *) exit 0 ;;
esac

# Cada `git push`/`git commit` do comando como "<dir>\t<marcador>\t<trocou>\t<refs>" (ver
# git_targets.py). O hook roda ANTES do comando: se ele troca de branch antes do push/commit,
# a branch final é desconhecida e o guard libera (rede de segurança, não trava).
targets="$(printf '%s' "$event" | "$PY" "$HERE/git_targets.py" push commit 2>/dev/null)"
[ -n "$targets" ] || exit 0

# Branches locais enviadas: HEAD, :multi e :unknown → branch do checkout; nome de branch local →
# ela mesma; tag, SHA ou ref remoto → nenhuma. $1 = repo, $2 = refs.
branches_sent() {
  if [ -n "${HARNESS_GUARD_BRANCH+x}" ]; then
    printf '%s\n' "$HARNESS_GUARD_BRANCH"   # seam de teste
    return
  fi
  current="$(git -C "$1" branch --show-current 2>/dev/null || true)"
  for ref in $2; do
    case "$ref" in
      HEAD|:*) printf '%s\n' "$current" ;;
      refs/heads/*) printf '%s\n' "${ref#refs/heads/}" ;;
      *) if git -C "$1" show-ref --verify --quiet "refs/heads/$ref" 2>/dev/null; then
           printf '%s\n' "$ref"
         fi ;;
    esac
  done
}

# Aviso (não-bloqueio): checkout principal numa feature branch. $1 = repo.
warn_main_checkout() {
  if [ -n "${HARNESS_GUARD_BRANCH+x}" ]; then
    branch="$HARNESS_GUARD_BRANCH"
  else
    branch="$(git -C "$1" branch --show-current 2>/dev/null || true)"
  fi
  case "$branch" in ''|main|master) return 0 ;; esac
  if [ -n "${HARNESS_GUARD_IN_WORKTREE:-}" ]; then
    in_wt="$HARNESS_GUARD_IN_WORKTREE"
  else
    gd="$(git -C "$1" rev-parse --absolute-git-dir 2>/dev/null || echo __a)"
    gcd="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || echo __b)"
    gd="$(cd "$gd" 2>/dev/null && pwd -P || echo "$gd")"
    gcd="$(cd "$gcd" 2>/dev/null && pwd -P || echo "$gcd")"
    if [ "$gd" = "$gcd" ]; then in_wt=0; else in_wt=1; fi
  fi
  if [ "$in_wt" = "0" ]; then
    echo "harness guard: trabalhando no checkout principal numa feature branch ('$branch') — considere um worktree." >&2
  fi
}

# Retorna 2 se a PR da branch está MERGED. $1 = repo, $2 = branch.
check_branch() {
  case "$2" in ''|main|master) return 0 ;; esac   # main/sem-branch não gera órfão de feature
  if [ -n "${HARNESS_GUARD_GH_CMD+x}" ]; then
    state="$(sh -c "$HARNESS_GUARD_GH_CMD" 2>/dev/null || true)"
  else
    if ! command -v gh >/dev/null 2>&1; then
      echo "harness guard: 'gh' ausente — anti-órfão não checado (fail-open)." >&2
      return 0
    fi
    # Sem `set -e`: cd ou gh falhando deixam state vazio (fail-open abaixo).
    state="$(cd "$1" 2>/dev/null && gh pr view "$2" --json state -q .state 2>/dev/null)"
  fi
  state="$(printf '%s' "$state" | tr -d '[:space:]')"

  if [ -z "$state" ]; then
    echo "harness guard: estado da PR indisponível (gh sem resposta) — anti-órfão não checado (fail-open)." >&2
    return 0
  fi

  if [ "$state" = "MERGED" ]; then
    echo "BLOQUEADO: a PR da branch '$2' já está MERGED — commits/pushes aqui ficam órfãos. Crie uma branch nova a partir da main." >&2
    return 2
  fi
  return 0
}

tab="$(printf '\t')"
rc=0
warned=" "
checked=" "
while IFS="$tab" read -r target_dir marker switched refs; do
  : "$marker"   # o marcador do gate não burla o anti-órfão
  [ -n "$refs" ] || continue   # push que só apaga: nada enviado
  if [ "$switched" = "1" ]; then
    echo "harness guard: o comando troca de branch antes do commit/push — anti-órfão não checado." >&2
    continue
  fi
  if [ -n "${HARNESS_GUARD_DIR:-}" ]; then
    dir="$HARNESS_GUARD_DIR"
  else
    dir="$(git -C "$target_dir" rev-parse --show-toplevel 2>/dev/null || echo "$target_dir")"
  fi
  case "$warned" in *" $dir "*) ;; *) warn_main_checkout "$dir"; warned="$warned$dir " ;; esac
  for branch in $(branches_sent "$dir" "$refs"); do
    case "$checked" in *" $dir|$branch "*) continue ;; esac
    checked="$checked$dir|$branch "
    check_branch "$dir" "$branch" || rc=2
  done
done <<TARGETS
$targets
TARGETS
exit "$rc"
