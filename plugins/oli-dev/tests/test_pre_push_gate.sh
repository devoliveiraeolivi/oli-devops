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

echo "pre_push_gate: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
