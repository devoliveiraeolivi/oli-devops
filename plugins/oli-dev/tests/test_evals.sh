#!/usr/bin/env sh
set -eu
# SC2015: A && B || C aqui é intencional (pwd -W só existe no Git-Bash/Windows; fallback pwd).
# shellcheck disable=SC2015
HERE="$(cd "$(dirname "$0")" && pwd -W 2>/dev/null || pwd)"
EV="$HERE/../evals/evals.json"
[ -f "$EV" ] || { echo "FAIL: evals.json missing" >&2; exit 1; }
PYTHON="$(command -v python3 || command -v python)" || { echo "FAIL: no python interpreter found (need python3 or python)" >&2; exit 1; }
"$PYTHON" - "$EV" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
assert isinstance(data, list) and len(data) >= 5, "need >=5 scenarios"
need = {"skip_precode_review","non_opus_main","broken_test_push","finalize_unmerged","resume_from_spec"}
ids = {s["id"] for s in data}
missing = need - ids
assert not missing, f"missing scenarios: {missing}"
for s in data:
    for k in ("id","scenario","pressure","expected_gate"):
        assert k in s and s[k], f"{s.get('id')} missing {k}"
print("OK evals")
PY
echo "PASS test_evals"
