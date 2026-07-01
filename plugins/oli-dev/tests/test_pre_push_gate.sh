#!/usr/bin/env sh
# NOTE: no `set -e` — we deliberately capture non-zero exit codes (the gate returns 2 on block).
# With `set -e`, `sh "$GATE"` returning 2 would abort the whole test before `check` runs.
set -u
HERE="$(cd "$(dirname "$0")" && pwd -W 2>/dev/null || pwd)"
GATE="$HERE/../hooks/pre-push-gate.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
# run gate, capture rc WITHOUT tripping any -e; usage: rc=$(gate_rc <json> [env assignments...])
gate_rc() { json="$1"; shift; rc=0; printf '%s' "$json" | env "$@" sh "$GATE" >/dev/null 2>&1 || rc=$?; echo "$rc"; }
check() { if [ "$1" = "$2" ]; then pass=$((pass+1)); else echo "FAIL: $3 (got rc=$1, want $2)" >&2; fail=$((fail+1)); fi; }
# captura só o stderr do gate (o run() ecoa ">> <cmd>" em stderr antes de executar)
gate_err() { json="$1"; shift; printf '%s' "$json" | env "$@" sh "$GATE" 2>&1 >/dev/null; }
# fake uv: sempre sai 0 → deixa o gate compor+ecoar o cmd sem toolchain real
mkdir -p "$TMP/bin"; printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/uv"; chmod +x "$TMP/bin/uv"

# 1. Non-push command → exit 0
check "$(gate_rc '{"tool_input":{"command":"git status"}}')" 0 "non-push passes through"

# 2. False positive: text mentioning push but not a push command → exit 0
check "$(gate_rc '{"tool_input":{"command":"echo lembrar de git push depois"}}')" 0 "echo mentioning git push is not a push"

# 3. In-cycle marker present → exit 0 even though it IS a push (Fase 6 already ran the gate)
mkdir -p "$TMP/py"; printf '[project]\nname="x"\n' > "$TMP/py/pyproject.toml"
check "$(gate_rc '{"tool_input":{"command":"OLI_DEV_GATE_OK=1 git push"}}' OLI_DEV_GATE_DIR="$TMP/py" OLI_DEV_PYTHON_CMDS=false)" 0 "in-cycle marker skips gate"

# 4. Push in an unrecognized stack dir → exit 0 (don't block what we can't check)
mkdir -p "$TMP/empty"
check "$(gate_rc '{"tool_input":{"command":"git push origin main"}}' OLI_DEV_GATE_DIR="$TMP/empty")" 0 "unknown stack passes"

# 5. Push in a python stack whose checks FAIL → exit 2
check "$(gate_rc '{"tool_input":{"command":"git push"}}' OLI_DEV_GATE_DIR="$TMP/py" OLI_DEV_PYTHON_CMDS=false)" 2 "python failing check blocks"

# 5b. Env-prefixed push must still be gated (regression for quoted-value strip)
check "$(gate_rc '{"tool_input":{"command":"FOO=bar git push"}}' OLI_DEV_GATE_DIR="$TMP/py" OLI_DEV_PYTHON_CMDS=false)" 2 "env-prefixed push is gated"

# 6. Push in a python stack whose checks PASS → exit 0
check "$(gate_rc '{"tool_input":{"command":"git push"}}' OLI_DEV_GATE_DIR="$TMP/py" OLI_DEV_PYTHON_CMDS=true)" 0 "python passing check allows"

# 7. scripts/check.sh presente + falhando → gate o prefere e bloqueia (exit 2),
#    mesmo o fallback python passando.
mkdir -p "$TMP/withcheck/scripts"; printf '[project]\nname="x"\n' > "$TMP/withcheck/pyproject.toml"
printf '#!/bin/sh\nexit 1\n' > "$TMP/withcheck/scripts/check.sh"; chmod +x "$TMP/withcheck/scripts/check.sh"
check "$(gate_rc '{"tool_input":{"command":"git push"}}' OLI_DEV_GATE_DIR="$TMP/withcheck")" 2 "check.sh falhando bloqueia (preferido sobre fallback)"

# 8. scripts/check.sh presente + passando → gate roda e libera; marcador prova que rodou.
mkdir -p "$TMP/checkok/scripts"
printf '#!/bin/sh\ntouch "%s/checkok/ran"\nexit 0\n' "$TMP" > "$TMP/checkok/scripts/check.sh"; chmod +x "$TMP/checkok/scripts/check.sh"
check "$(gate_rc '{"tool_input":{"command":"git push"}}' OLI_DEV_GATE_DIR="$TMP/checkok")" 0 "check.sh passando libera"
if [ -f "$TMP/checkok/ran" ]; then pass=$((pass+1)); else echo "FAIL: check.sh realmente rodou (marcador ausente)" >&2; fail=$((fail+1)); fi

# 9. Override explícito OLI_DEV_PYTHON_CMDS vence o check.sh (escape hatch).
mkdir -p "$TMP/override/scripts"; printf '[project]\nname="x"\n' > "$TMP/override/pyproject.toml"
printf '#!/bin/sh\nexit 1\n' > "$TMP/override/scripts/check.sh"; chmod +x "$TMP/override/scripts/check.sh"
check "$(gate_rc '{"tool_input":{"command":"git push"}}' OLI_DEV_GATE_DIR="$TMP/override" OLI_DEV_PYTHON_CMDS=true)" 0 "override vence check.sh"

# 10. Fallback (sem check.sh): cmd composto tira black, mantém ruff format + mypy.
mkdir -p "$TMP/fb"; printf '[project]\nname="x"\n' > "$TMP/fb/pyproject.toml"
err10="$(gate_err '{"tool_input":{"command":"git push"}}' OLI_DEV_GATE_DIR="$TMP/fb" PATH="$TMP/bin:$PATH")"
if echo "$err10" | grep -q 'ruff format'; then pass=$((pass+1)); else echo "FAIL: fallback roda ruff format" >&2; fail=$((fail+1)); fi
if echo "$err10" | grep -q 'black'; then echo "FAIL: fallback não pode rodar black" >&2; fail=$((fail+1)); else pass=$((pass+1)); fi

# 11. Fallback mypy baseline-aware quando há .mypy-baseline.txt.
mkdir -p "$TMP/fbbl"; printf '[project]\nname="x"\n' > "$TMP/fbbl/pyproject.toml"; : > "$TMP/fbbl/.mypy-baseline.txt"
err11="$(gate_err '{"tool_input":{"command":"git push"}}' OLI_DEV_GATE_DIR="$TMP/fbbl" PATH="$TMP/bin:$PATH")"
if echo "$err11" | grep -q 'mypy-baseline filter'; then pass=$((pass+1)); else echo "FAIL: baseline presente → mypy-baseline filter" >&2; fail=$((fail+1)); fi

# 12. Fallback mypy cru quando NÃO há baseline.
err12="$(gate_err '{"tool_input":{"command":"git push"}}' OLI_DEV_GATE_DIR="$TMP/fb" PATH="$TMP/bin:$PATH")"
if echo "$err12" | grep -q 'mypy-baseline filter'; then echo "FAIL: sem baseline → mypy cru" >&2; fail=$((fail+1)); else pass=$((pass+1)); fi

echo "pre_push_gate: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
