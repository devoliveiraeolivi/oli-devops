#!/usr/bin/env sh
# NOTE: no `set -e` — we deliberately capture non-zero exit codes (the gate returns 2 on block).
# With `set -e`, `sh "$GATE"` returning 2 would abort the whole test before `check` runs.
set -u
# SC2015: A && B || C aqui é intencional (pwd -W só existe no Git-Bash/Windows; fallback pwd).
# shellcheck disable=SC2015
HERE="$(cd "$(dirname "$0")" && pwd -W 2>/dev/null || pwd)"
GATE="$HERE/../scripts/pre-push-gate.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
# run gate, capture rc WITHOUT tripping any -e; usage: rc=$(gate_rc <json> [env assignments...])
gate_rc() { json="$1"; shift; rc=0; printf '%s' "$json" | env "$@" "${HARNESS_TEST_SHELL:-sh}" "$GATE" >/dev/null 2>&1 || rc=$?; echo "$rc"; }
check() { if [ "$1" = "$2" ]; then pass=$((pass+1)); else echo "FAIL: $3 (got rc=$1, want $2)" >&2; fail=$((fail+1)); fi; }
# captura só o stderr do gate (o run() ecoa ">> <cmd>" em stderr antes de executar)
# SC2069: ordem intencional — captura stderr p/ asserts de mensagem, descarta stdout.
# shellcheck disable=SC2069
gate_err() { json="$1"; shift; printf '%s' "$json" | env "$@" "${HARNESS_TEST_SHELL:-sh}" "$GATE" 2>&1 >/dev/null; }
# fake uv: sempre sai 0 → deixa o gate compor+ecoar o cmd sem toolchain real
mkdir -p "$TMP/bin"; printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/uv"; chmod +x "$TMP/bin/uv"

# 1. Non-push command → exit 0
check "$(gate_rc '{"tool_input":{"command":"git status"}}')" 0 "non-push passes through"

# 2. False positive: text mentioning push but not a push command → exit 0
check "$(gate_rc '{"tool_input":{"command":"echo lembrar de git push depois"}}')" 0 "echo mentioning git push is not a push"

# 3. Gate marker present → exit 0 even though it IS a push (repo check already ran)
mkdir -p "$TMP/py"; printf '[project]\nname="x"\n' > "$TMP/py/pyproject.toml"
check "$(gate_rc '{"tool_input":{"command":"HARNESS_GATE_OK=1 git push"}}' HARNESS_GATE_DIR="$TMP/py" HARNESS_PYTHON_CMDS=false)" 0 "gate marker skips gate"

# 4. Push in an unrecognized stack dir → exit 0 (don't block what we can't check)
mkdir -p "$TMP/empty"
check "$(gate_rc '{"tool_input":{"command":"git push origin main"}}' HARNESS_GATE_DIR="$TMP/empty")" 0 "unknown stack passes"

# 5. Push in a python stack whose checks FAIL → exit 2
check "$(gate_rc '{"tool_input":{"command":"git push"}}' HARNESS_GATE_DIR="$TMP/py" HARNESS_PYTHON_CMDS=false)" 2 "python failing check blocks"

# 5b. Env-prefixed push must still be gated (regression for quoted-value strip)
check "$(gate_rc '{"tool_input":{"command":"FOO=bar git push"}}' HARNESS_GATE_DIR="$TMP/py" HARNESS_PYTHON_CMDS=false)" 2 "env-prefixed push is gated"

# 6. Push in a python stack whose checks PASS → exit 0
check "$(gate_rc '{"tool_input":{"command":"git push"}}' HARNESS_GATE_DIR="$TMP/py" HARNESS_PYTHON_CMDS=true)" 0 "python passing check allows"

# 7. scripts/check.sh presente + falhando → gate o prefere e bloqueia (exit 2),
#    mesmo o fallback python passando.
mkdir -p "$TMP/withcheck/scripts"; printf '[project]\nname="x"\n' > "$TMP/withcheck/pyproject.toml"
printf '#!/bin/sh\nexit 1\n' > "$TMP/withcheck/scripts/check.sh"; chmod +x "$TMP/withcheck/scripts/check.sh"
check "$(gate_rc '{"tool_input":{"command":"git push"}}' HARNESS_GATE_DIR="$TMP/withcheck")" 2 "check.sh falhando bloqueia (preferido sobre fallback)"

# 8. scripts/check.sh presente + passando → gate roda e libera; marcador prova que rodou.
mkdir -p "$TMP/checkok/scripts"
printf '#!/bin/sh\ntouch "%s/checkok/ran"\nexit 0\n' "$TMP" > "$TMP/checkok/scripts/check.sh"; chmod +x "$TMP/checkok/scripts/check.sh"
check "$(gate_rc '{"tool_input":{"command":"git push"}}' HARNESS_GATE_DIR="$TMP/checkok")" 0 "check.sh passando libera"
if [ -f "$TMP/checkok/ran" ]; then pass=$((pass+1)); else echo "FAIL: check.sh realmente rodou (marcador ausente)" >&2; fail=$((fail+1)); fi

# 9. Override explícito HARNESS_PYTHON_CMDS vence o check.sh (escape hatch).
mkdir -p "$TMP/override/scripts"; printf '[project]\nname="x"\n' > "$TMP/override/pyproject.toml"
printf '#!/bin/sh\nexit 1\n' > "$TMP/override/scripts/check.sh"; chmod +x "$TMP/override/scripts/check.sh"
check "$(gate_rc '{"tool_input":{"command":"git push"}}' HARNESS_GATE_DIR="$TMP/override" HARNESS_PYTHON_CMDS=true)" 0 "override vence check.sh"

# 10. Fallback (sem check.sh): cmd composto tira black, mantém ruff format + mypy.
mkdir -p "$TMP/fb"; printf '[project]\nname="x"\n' > "$TMP/fb/pyproject.toml"
err10="$(gate_err '{"tool_input":{"command":"git push"}}' HARNESS_GATE_DIR="$TMP/fb" PATH="$TMP/bin:$PATH")"
if echo "$err10" | grep -q 'ruff format'; then pass=$((pass+1)); else echo "FAIL: fallback roda ruff format" >&2; fail=$((fail+1)); fi
if echo "$err10" | grep -q 'black'; then echo "FAIL: fallback não pode rodar black" >&2; fail=$((fail+1)); else pass=$((pass+1)); fi

# 11. Fallback mypy baseline-aware quando há .mypy-baseline.txt.
mkdir -p "$TMP/fbbl"; printf '[project]\nname="x"\n' > "$TMP/fbbl/pyproject.toml"; : > "$TMP/fbbl/.mypy-baseline.txt"
err11="$(gate_err '{"tool_input":{"command":"git push"}}' HARNESS_GATE_DIR="$TMP/fbbl" PATH="$TMP/bin:$PATH")"
if echo "$err11" | grep -q 'mypy-baseline filter'; then pass=$((pass+1)); else echo "FAIL: baseline presente → mypy-baseline filter" >&2; fail=$((fail+1)); fi

# 12. Fallback mypy cru quando NÃO há baseline.
err12="$(gate_err '{"tool_input":{"command":"git push"}}' HARNESS_GATE_DIR="$TMP/fb" PATH="$TMP/bin:$PATH")"
if echo "$err12" | grep -q 'mypy-baseline filter'; then echo "FAIL: sem baseline → mypy cru" >&2; fail=$((fail+1)); else pass=$((pass+1)); fi

# 13. Push composto: `cd <repo> && git push` roda o gate no repo do cd (checks falhando → 2).
check "$(gate_rc "$(printf '{"tool_input":{"command":"cd %s && git push"}}' "$TMP/py")" HARNESS_PYTHON_CMDS=false)" 2 "cd && git push is gated in the cd target"
# 14. `git -C <repo> push` roda o gate no repo do -C.
check "$(gate_rc "$(printf '{"tool_input":{"command":"git -C %s push"}}' "$TMP/py")" HARNESS_PYTHON_CMDS=false)" 2 "git -C push is gated"
# 15. Marcador no segmento do push (depois do cd) libera; em mensagem de commit, não.
check "$(gate_rc "$(printf '{"tool_input":{"command":"cd %s && HARNESS_GATE_OK=1 git push"}}' "$TMP/py")" HARNESS_PYTHON_CMDS=false)" 0 "gate marker on the push command skips gate"
check "$(gate_rc "$(printf '{"tool_input":{"command":"git commit -m HARNESS_GATE_OK=1 && git -C %s push"}}' "$TMP/py")" HARNESS_PYTHON_CMDS=false)" 2 "marker outside the push command does not skip gate"

# 16-30. Repo git real. O hook roda ANTES do comando: valida quando o push envia o HEAD atual;
#        quando não dá para saber (outro ref, troca de branch antes), libera — o CI valida o SHA.
GITPY="$TMP/gitpy"
mkdir -p "$GITPY"; git -C "$GITPY" init -q -b main
printf '[project]\nname="x"\n' > "$GITPY/pyproject.toml"
git -C "$GITPY" add pyproject.toml
git -C "$GITPY" -c user.email=t@t -c user.name=t commit -q -m base
git -C "$GITPY" branch old
git -C "$GITPY" -c user.email=t@t -c user.name=t commit -q --allow-empty -m second
ev() { printf '{"tool_input":{"command":"%s"},"cwd":"%s"}' "$1" "$GITPY"; }
# Pushes do HEAD atual: o gate roda (checks falhando → 2).
for cmd in "git push" "git push origin main" "git push -u origin HEAD 2>&1 | tail -5" \
           "git push origin main # retry" "timeout 300 git push" "if true; then git push; fi" \
           "(cd $GITPY && git push)"; do
  check "$(gate_rc "$(ev "$cmd")" HARNESS_PYTHON_CMDS=false)" 2 "gated: $cmd"
done
check "$(gate_rc "$(printf '{"tool_input":{"command":"# push it (it'"'"'s new)\\ngit push"},"cwd":"%s"}' "$GITPY")" HARNESS_PYTHON_CMDS=false)" 2 "gated after a comment line with an apostrophe"
check "$(gate_rc "$(ev "git push")" HARNESS_PYTHON_CMDS=true)" 0 "push of HEAD with passing checks passes"
# Commit + push na mesma linha: a árvore já tem o que vai ser commitado → o gate roda nela.
printf 'dirty\n' >> "$GITPY/pyproject.toml"
check "$(gate_rc "$(ev "git commit -am x && git push")" HARNESS_PYTHON_CMDS=true)" 0 "commit && push with passing checks passes"
check "$(gate_rc "$(ev "git commit -am x && git push")" HARNESS_PYTHON_CMDS=false)" 2 "commit && push with failing checks blocks"
git -C "$GITPY" checkout -q -- pyproject.toml
# Sem como validar aqui → libera (mesmo com checks falhando).
for cmd in "git push origin old" "git push --tags origin" "git push origin --delete old" \
           "git checkout -b feat/new && git push -u origin feat/new" "git tag v1 && git push origin v1"; do
  check "$(gate_rc "$(ev "$cmd")" HARNESS_PYTHON_CMDS=false)" 0 "not validated here: $cmd"
done
check "$(gate_rc "$(printf '{"tool_input":{"command":"cat > N.md <<'"'"'EOF'"'"'\\ngit push origin v9\\nEOF"},"cwd":"%s"}' "$GITPY")" HARNESS_PYTHON_CMDS=false)" 0 "heredoc body is not a push"
check "$(gate_rc "$(ev "HARNESS_GATE_OK=1 git push")" HARNESS_PYTHON_CMDS=false)" 0 "gate marker still skips"
# Todo push do comando é checado, não só o primeiro.
check "$(gate_rc "$(printf '{"tool_input":{"command":"git -C %s push && git -C %s push"}}' "$TMP/empty" "$TMP/py")" HARNESS_PYTHON_CMDS=false)" 2 "every push target is gated"

echo "pre_push_gate: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
