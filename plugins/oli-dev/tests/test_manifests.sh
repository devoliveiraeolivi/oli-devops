#!/usr/bin/env sh
set -eu
ROOT="$(cd "$(dirname "$0")/../../.." && pwd -W 2>/dev/null || pwd)"   # repo root (Windows-compatible path for Python)
fail() { echo "FAIL: $1" >&2; exit 1; }

# JSON validity (python is always present in these repos)
python -c "import json,sys; json.load(open('$ROOT/.claude-plugin/marketplace.json'))" \
  || fail "marketplace.json is not valid JSON"
python -c "import json,sys; json.load(open('$ROOT/plugins/oli-dev/.claude-plugin/plugin.json'))" \
  || fail "plugin.json is not valid JSON"

# Required fields
python - "$ROOT" <<'PY'
import json, sys
root = sys.argv[1]
mk = json.load(open(f"{root}/.claude-plugin/marketplace.json"))
assert mk.get("name") == "oli-devops", mk.get("name")
plugins = mk.get("plugins", [])
assert any(p.get("name") == "oli-dev" for p in plugins), "oli-dev not registered in marketplace"
pj = json.load(open(f"{root}/plugins/oli-dev/.claude-plugin/plugin.json"))
assert pj.get("name") == "oli-dev", pj.get("name")
assert "description" in pj
assert "version" not in pj, "do NOT pin version while iterating (stale-cache trap per docs)"
print("OK manifests")
PY

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
echo "PASS test_manifests"
