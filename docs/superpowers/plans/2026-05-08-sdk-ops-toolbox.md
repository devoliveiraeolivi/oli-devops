# SDK Ops Toolbox — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add operations tooling to `oli-devops` for managing the `oli-sdk` lifecycle across consumers — Vault secret seed, security-token rotation, version-pin audit, and smoke probe against Salesforce sandbox. Cross-language by design (works for both Python and JS consumers).

**Architecture:** `oli-devops` today is a **security baseline** (pre-commit hooks + reusable workflows). This plan **expands its scope** to include cross-cutting operations tooling. The new scripts live in `scripts/sdk/` (parallel to existing `scripts/` with security wrappers), backed by a `config/consumers.toml` registry that lists every OLI consumer repo and its language. Scripts are language-agnostic where possible (bash + jq + curl) and language-specific where the SDK itself is invoked (`tsx` for JS, `uv run` for Python).

The alternative considered — keeping ops tooling inside `oli-sdk` itself — was rejected because (a) the SDK's spec mãe says "library only, doesn't run anywhere", (b) cross-language ops would require duplicate JS+Python CLIs, and (c) ops cadence is independent of SDK release cadence. See `oli-sdk` Spec 12 §5.4 (pass-through) and the brainstorm decision logged below as D1.

**Tech Stack:** bash 5+, jq, curl, hashicorp `vault` CLI (already required by other ops), `tsx` (npm exec), `uv run`, `gh` CLI (read-only, for consumer repo discovery).

**Pre-conditions external to this plan:**
- `oli-sdk` v0.12.0 is published (after PR #38 merge + tag).
- Vault is reachable; ops user has admin credentials in `VAULT_ADDR`/`VAULT_TOKEN`.
- Salesforce sandbox org exists and is the target of the smoke probe (separate from production tenants per consumer).
- v1.2.0 of `oli-devops` (quality hooks plan) has shipped, so this plan targets v1.3.0.

---

## Strategy decisions (fixed unless owner overrides)

| ID | Decision | Status |
|---|---|---|
| **D1** | **Scope expansion of `oli-devops`** from "security baseline" to "security baseline **+ cross-cutting ops tooling**". README and CLAUDE.md headers updated to reflect dual scope. Reversible: if the ops tooling outgrows the repo, extract to `oli-ops-tools` later — the scripts are self-contained and have no compile-time coupling to the security baseline. **Owner override accepted with this plan**: alternative is a new repo, which adds CI/release/Renovate overhead disproportionate to 4 scripts. | 🔄 needs owner confirmation |
| **D2** | **4 scripts in initial scope**: `seed-secret.sh`, `rotate-secret.sh`, `audit-versions.ts`, `smoke-salesforce.{ts,py}`. Anything beyond this is a new plan. Specifically out of scope: secret backup/restore, full DR drill, Salesforce metadata diff, anything tribunal-related (lives in `monitoramento`/`probe` skills already). | ✅ |
| **D3** | **Bilingual smoke probe**: ship both `smoke-salesforce.ts` (executes via `npx tsx`) and `smoke-salesforce.py` (executes via `uv run`). Cross-language because the SDK itself is bilingual — JS consumers need to see JS-SDK working, Python consumers need Python-SDK. Single `smoke-salesforce.sh` dispatcher detects which to run via flag. | ✅ |
| **D4** | **Consumer registry as `config/consumers.toml`** (declarative). Format: `[[consumer]] name = "oli-app", language = "js", repo = "github:...", sdk_path = "package.json:dependencies.@devoliveiraeolivi/oli-sdk", vault_path = "apis/salesforce-oli-app"`. Audit script reads this to know what to query. Single source of truth, no `gh search` magic. Adding/removing a consumer is a PR. | ✅ |
| **D5** | **Vault auth**: scripts read `VAULT_ADDR` + `VAULT_TOKEN` env vars (existing convention; same as runbooks). No new auth mechanism. Scripts that mutate secrets (`seed-secret.sh`, `rotate-secret.sh`) print the policy required by the token before exiting on auth failure, so ops can fix permissions. | ✅ |
| **D6** | **Release as `oli-devops v1.3.0`** (MINOR — additive scope expansion). v1.2.0 from the quality-hooks plan must merge first. Renovate proposes the bump to consumers; nothing in `oli-devops` v1.2.0 → v1.3.0 affects existing pre-commit configs or workflows. | ✅ |
| **D7** | **No CLI binary**: scripts are invoked directly (`./scripts/sdk/seed-secret.sh ...`), not via `npm bin`. Reason: bash scripts in `scripts/` is the existing oli-devops pattern (`gitleaks-protect.sh`, `trivy-fs.sh`); we extend that pattern rather than introducing a new packaging concept. Operators clone `oli-devops` (or copy the script) and run. | ✅ |
| **D8** | **Smoke probe is read-only**: calls `describe()` on a single SObject (configurable, default `Account`). Never mutates Salesforce data. Cheap, fast, no governor-limit concern. Used in CI sanity checks and ad-hoc ops. | ✅ |
| **D9** | **Audit thresholds**: drift_status = `current` (latest), `behind_minor` (1 minor behind), `behind_major` (≥2 minor behind), `unpinned` (`*` or missing). Exit code: 0 if all current, 1 if any `behind_major` or `unpinned`, 0-with-warning otherwise. CI-friendly. | ✅ |
| **D10** | **No automatic notification on audit failure** in v1.3.0. Audit is run manually by ops or in scheduled GitHub Action; output goes to stdout/job log. Notification → Slack/Teams is a future plan when there's >1 consumer where it matters. | ✅ |

---

## File structure

**Files to create:**

- `scripts/sdk/seed-secret.sh` — populate `apis/salesforce-<consumer>` from prompts (or env vars in non-interactive mode).
- `scripts/sdk/rotate-secret.sh` — replace `security_token` (or `password`) on an existing Vault path; preserves other fields.
- `scripts/sdk/audit-versions.ts` — read `config/consumers.toml`, query each repo's pinned SDK version, print a table.
- `scripts/sdk/smoke-salesforce.sh` — dispatcher: chooses `.ts` or `.py` impl based on `--language` flag (default: both).
- `scripts/sdk/smoke-salesforce.ts` — JS impl: imports `@devoliveiraeolivi/oli-sdk/salesforce`, runs `describe("Account")`, exits 0 on OK.
- `scripts/sdk/smoke-salesforce.py` — Python impl: same behavior using `oli_sdk.salesforce`.
- `scripts/sdk/_lib.sh` — shared helpers (Vault auth check, JSON validation, error formatting).
- `scripts/sdk/_lib.ts` — shared TS helpers (parse `consumers.toml`, format table output).
- `config/consumers.toml` — declarative consumer registry.
- `tests/sdk/seed-secret.bats` — bats-core tests for seed script (mocked vault CLI via stub).
- `tests/sdk/rotate-secret.bats` — bats tests for rotate.
- `tests/sdk/audit-versions.test.ts` — vitest tests with fixture toml files + mocked gh API.
- `docs/SDK-OPS.md` — operational runbook: when to run each script, expected output, troubleshooting.

**Files to modify:**

- `README.md` — update purpose statement to "security baseline + ops tooling"; add SDK ops section linking to `docs/SDK-OPS.md`.
- `CLAUDE.md` — same scope expansion in the "Purpose" section.
- `CHANGELOG.md` — add `[v1.3.0]` entry.
- `package.json` (root, if needed) — add `tsx`, `vitest`, `@iarna/toml` as devDeps to support TS scripts. (Verify whether oli-devops already has a package.json; if not, this plan adds one.)

---

## Phase A — Scaffolding + registry (Tasks A.1–A.3)

### Task A.1: Create branch and scope-expansion docs

**Files:**
- Modify: `README.md`, `CLAUDE.md`

- [ ] **Step 1: Create branch off `main`**

```bash
cd c:/Apps/oli-devops
git checkout main && git pull
git checkout -b feat/sdk-ops-toolbox
```

- [ ] **Step 2: Update `README.md` purpose**

Change the second-line description from:

```
Centralized security baseline for OLI repositories.
```

to:

```
Centralized security baseline + cross-cutting operations tooling for OLI repositories.
```

Add a new section after "Quick start (consumer repo)":

```markdown
## SDK Ops Toolbox (v1.3.0+)

Scripts in `scripts/sdk/` manage the `oli-sdk` lifecycle across consumers:

- `seed-secret.sh <consumer>` — populate Vault path `apis/salesforce-<consumer>`.
- `rotate-secret.sh <consumer> --field security_token` — rotate one credential field.
- `audit-versions.ts` — report SDK version drift across consumers (reads `config/consumers.toml`).
- `smoke-salesforce.sh --consumer <consumer>` — verify Vault → SDK → Salesforce sandbox chain.

See [`docs/SDK-OPS.md`](docs/SDK-OPS.md) for the operational runbook.
```

- [ ] **Step 3: Update `CLAUDE.md` Purpose**

Change "This is the **centralized security baseline** for all OLI repos." to:

```markdown
This is the **centralized security baseline + ops tooling** for all OLI repos. It contains (a) pre-commit security hooks + reusable security workflow (`scripts/`), and (b) cross-cutting operations scripts for managing `oli-sdk` lifecycle across consumers (`scripts/sdk/`). Both areas evolve independently; bumps are MINOR for additive changes, MAJOR for renames or removals.
```

- [ ] **Step 4: Commit**

```bash
git add README.md CLAUDE.md
git commit -m "docs: expand oli-devops scope to include SDK ops tooling (D1)"
```

---

### Task A.2: Add `config/consumers.toml` registry

**Files:**
- Create: `config/consumers.toml`

- [ ] **Step 1: Create the file**

```toml
# Consumer registry for oli-sdk lifecycle ops.
# Each entry describes one repo that imports @devoliveiraeolivi/oli-sdk or oli-sdk Python.
# Audit reads this to query pinned SDK versions; smoke probe reads vault_path.

[[consumer]]
name = "oli-app"
language = "js"
repo = "github:devoliveiraeolivi/oli-app"
sdk_pin_path = "package.json:dependencies.@devoliveiraeolivi/oli-sdk"
vault_path = "apis/salesforce-oli-app"
imports_salesforce = true

[[consumer]]
name = "oli-news"
language = "python"
repo = "github:devoliveiraeolivi/oli-news"
sdk_pin_path = "pyproject.toml:project.dependencies"
vault_path = "apis/salesforce-oli-news"
imports_salesforce = true

[[consumer]]
name = "oli-indexer"
language = "python"
repo = "github:devoliveiraeolivi/oli-indexer"
sdk_pin_path = "pyproject.toml:project.dependencies"
vault_path = "apis/salesforce-oli-indexer"
imports_salesforce = true

[[consumer]]
name = "anp-bi-etl"
language = "python"
repo = "github:devoliveiraeolivi/anp-bi-etl"
sdk_pin_path = "pyproject.toml:project.dependencies"
vault_path = "apis/salesforce-anp-bi-etl"
imports_salesforce = true

[[consumer]]
name = "salesforce-etl"
language = "python"
repo = "github:devoliveiraeolivi/salesforce-etl"
sdk_pin_path = "pyproject.toml:project.dependencies"
vault_path = "apis/salesforce-salesforce-etl"
imports_salesforce = true

# Add new consumers here as they adopt the SDK.
```

- [ ] **Step 2: Commit**

```bash
git add config/consumers.toml
git commit -m "feat(sdk-ops): add consumer registry"
```

---

### Task A.3: Add `package.json` scaffolding (if absent)

**Files:**
- Modify or create: `package.json` at repo root

- [ ] **Step 1: Check if `package.json` exists**

If not, create at repo root:

```json
{
  "name": "@devoliveiraeolivi/oli-devops",
  "version": "1.3.0",
  "private": true,
  "description": "OLI security baseline + ops tooling — internal use",
  "type": "module",
  "scripts": {
    "test": "vitest run",
    "audit:sdk": "tsx scripts/sdk/audit-versions.ts"
  },
  "devDependencies": {
    "@iarna/toml": "^4.0.0",
    "tsx": "^4.0.0",
    "typescript": "~6.0",
    "vitest": "^4.1.5"
  }
}
```

- [ ] **Step 2: `npm install`**

- [ ] **Step 3: Commit**

```bash
git add package.json package-lock.json
git commit -m "build: add npm package.json for TS scripts (tsx + vitest)"
```

---

## Phase B — Vault scripts (Tasks B.1–B.4)

### Task B.1: `_lib.sh` shared helpers (TDD via bats-core)

**Files:**
- Create: `scripts/sdk/_lib.sh`
- Create: `tests/sdk/lib.bats`

- [ ] **Step 1: Write failing bats tests**

```bash
# tests/sdk/lib.bats
#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../../scripts/sdk/_lib.sh"
}

@test "require_env exits with hint when env var missing" {
  unset VAULT_ADDR
  run require_env VAULT_ADDR
  [ "$status" -eq 2 ]
  [[ "$output" == *"VAULT_ADDR is required"* ]]
}

@test "require_env passes when env var set" {
  export VAULT_ADDR="http://localhost:8200"
  run require_env VAULT_ADDR
  [ "$status" -eq 0 ]
}

@test "json_required_field extracts string field" {
  local payload='{"username":"u","password":"p"}'
  run json_required_field "$payload" username
  [ "$status" -eq 0 ]
  [ "$output" = "u" ]
}

@test "json_required_field exits 3 when field missing" {
  local payload='{"username":"u"}'
  run json_required_field "$payload" password
  [ "$status" -eq 3 ]
  [[ "$output" == *"password is required"* ]]
}
```

- [ ] **Step 2: Run, verify FAIL** — `bats tests/sdk/lib.bats` (file not found).

- [ ] **Step 3: Implement `_lib.sh`**

```bash
#!/usr/bin/env bash
# Shared helpers for sdk-ops scripts. Source this; do not execute.

set -euo pipefail

# require_env VAR_NAME — exit 2 with hint if VAR_NAME is unset or empty.
require_env() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo "ERROR: $name is required (set it in your shell or .env)" >&2
    return 2
  fi
}

# json_required_field PAYLOAD FIELD — print field value, exit 3 if missing.
# Uses jq; assumes jq is on PATH (already a dep of trivy-fs.sh).
json_required_field() {
  local payload="$1"
  local field="$2"
  local value
  value="$(printf '%s' "$payload" | jq -er --arg f "$field" '.[$f]')" || {
    echo "ERROR: $field is required in JSON payload" >&2
    return 3
  }
  printf '%s' "$value"
}

# vault_kv_read PATH — wrapper around `vault kv get -format=json` returning data.data JSON.
vault_kv_read() {
  local path="$1"
  vault kv get -format=json -mount=secret "$path" | jq -e '.data.data'
}

# vault_kv_write PATH JSON — wrapper around `vault kv put -mount=secret`.
vault_kv_write() {
  local path="$1"
  local json="$2"
  printf '%s' "$json" | vault kv put -mount=secret "$path" -
}
```

- [ ] **Step 4: Run, verify PASS** — `bats tests/sdk/lib.bats` (4 passing).

- [ ] **Step 5: Commit**

```bash
git add scripts/sdk/_lib.sh tests/sdk/lib.bats
git commit -m "feat(sdk-ops): add _lib.sh shared helpers (TDD via bats)"
```

---

### Task B.2: `seed-secret.sh` (TDD)

**Files:**
- Create: `scripts/sdk/seed-secret.sh`
- Create: `tests/sdk/seed-secret.bats`

- [ ] **Step 1: Write failing tests**

```bash
# tests/sdk/seed-secret.bats
#!/usr/bin/env bats

setup() {
  PATH="${BATS_TEST_DIRNAME}/stubs:$PATH"
  export VAULT_ADDR="http://localhost:8200"
  export VAULT_TOKEN="stub"
  export STUB_VAULT_RECORDED="$BATS_TEST_TMPDIR/vault-recorded.txt"
  : > "$STUB_VAULT_RECORDED"
}

@test "seed-secret.sh writes Vault path with all required fields" {
  run scripts/sdk/seed-secret.sh \
    --consumer oli-app \
    --username u@example.com \
    --password "p@ss" \
    --security-token "tokABC" \
    --domain login
  [ "$status" -eq 0 ]
  [[ "$output" == *"seeded apis/salesforce-oli-app"* ]]
  grep -q '"username":"u@example.com"' "$STUB_VAULT_RECORDED"
  grep -q '"security_token":"tokABC"' "$STUB_VAULT_RECORDED"
}

@test "seed-secret.sh exits 2 when --consumer missing" {
  run scripts/sdk/seed-secret.sh --username u --password p --security-token t
  [ "$status" -eq 2 ]
  [[ "$output" == *"--consumer is required"* ]]
}

@test "seed-secret.sh defaults domain to 'login' when omitted" {
  run scripts/sdk/seed-secret.sh \
    --consumer oli-test --username u --password p --security-token t
  [ "$status" -eq 0 ]
  grep -q '"domain":"login"' "$STUB_VAULT_RECORDED"
}
```

(Stub for `vault` lives at `tests/sdk/stubs/vault` — appends invocation args to `$STUB_VAULT_RECORDED`. Add as part of step 3.)

- [ ] **Step 2: Run, verify FAIL** — `bats tests/sdk/seed-secret.bats`.

- [ ] **Step 3: Implement `seed-secret.sh`**

```bash
#!/usr/bin/env bash
# seed-secret.sh — populate apis/salesforce-<consumer> in Vault.
#
# Usage:
#   scripts/sdk/seed-secret.sh \
#     --consumer oli-app \
#     --username user@example.com \
#     --password 'p@ss' \
#     --security-token tokABC \
#     [--domain login]
#
# Requires: VAULT_ADDR, VAULT_TOKEN; vault CLI on PATH.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

consumer=""
username=""
password=""
security_token=""
domain="login"

while [ $# -gt 0 ]; do
  case "$1" in
    --consumer) consumer="$2"; shift 2 ;;
    --username) username="$2"; shift 2 ;;
    --password) password="$2"; shift 2 ;;
    --security-token) security_token="$2"; shift 2 ;;
    --domain) domain="$2"; shift 2 ;;
    *) echo "ERROR: unknown flag $1" >&2; exit 2 ;;
  esac
done

[ -z "$consumer" ] && { echo "ERROR: --consumer is required" >&2; exit 2; }
[ -z "$username" ] && { echo "ERROR: --username is required" >&2; exit 2; }
[ -z "$password" ] && { echo "ERROR: --password is required" >&2; exit 2; }
[ -z "$security_token" ] && { echo "ERROR: --security-token is required" >&2; exit 2; }

require_env VAULT_ADDR
require_env VAULT_TOKEN

payload=$(jq -nc \
  --arg u "$username" --arg p "$password" --arg t "$security_token" --arg d "$domain" \
  '{username:$u, password:$p, security_token:$t, domain:$d}')

vault_kv_write "apis/salesforce-$consumer" "$payload"
echo "seeded apis/salesforce-$consumer"
```

(Plus stub `tests/sdk/stubs/vault`:)

```bash
#!/usr/bin/env bash
# Test stub for vault CLI. Appends args to $STUB_VAULT_RECORDED.
echo "$@ <<< $(cat /dev/stdin 2>/dev/null || true)" >> "${STUB_VAULT_RECORDED:-/tmp/stub-vault.txt}"
exit 0
```

(Make stub executable: `chmod +x tests/sdk/stubs/vault`.)

- [ ] **Step 4: Run, verify PASS**

- [ ] **Step 5: Commit**

```bash
git add scripts/sdk/seed-secret.sh tests/sdk/seed-secret.bats tests/sdk/stubs/vault
git commit -m "feat(sdk-ops): add seed-secret.sh (TDD)"
```

---

### Task B.3: `rotate-secret.sh` (TDD)

**Files:**
- Create: `scripts/sdk/rotate-secret.sh`
- Create: `tests/sdk/rotate-secret.bats`

- [ ] **Step 1: Tests** (rotate one field, preserve others; exit 4 if path doesn't exist; exit 5 if rotated value equals current value to prevent no-op).

[Test code follows the same pattern as B.2 — full bats file with 4 cases. Implement after seeing failure.]

- [ ] **Step 2: Implementation** — read existing payload via `vault_kv_read`, apply jq patch on the requested field, write back via `vault_kv_write`. Field must be one of `password|security_token`.

- [ ] **Step 3: Commit**

---

## Phase C — Audit + smoke (Tasks C.1–C.3)

### Task C.1: `audit-versions.ts` (TDD via vitest)

**Files:**
- Create: `scripts/sdk/audit-versions.ts`
- Create: `scripts/sdk/_lib.ts`
- Create: `tests/sdk/audit-versions.test.ts`

- [ ] **Step 1: Test fixtures + failing test**

```typescript
// tests/sdk/audit-versions.test.ts
import { describe, it, expect, vi } from "vitest";
import { auditVersions, type Consumer, type AuditRow } from "../../scripts/sdk/audit-versions.js";

describe("auditVersions", () => {
  it("classifies consumers as current / behind_minor / behind_major / unpinned", async () => {
    const consumers: Consumer[] = [
      { name: "a", language: "js", repo: "github:x/a", sdkPinPath: "package.json", vaultPath: "v/a", importsSalesforce: true },
      { name: "b", language: "python", repo: "github:x/b", sdkPinPath: "pyproject.toml", vaultPath: "v/b", importsSalesforce: false },
    ];
    const fakeFetcher = vi.fn(async (c) => {
      if (c.name === "a") return "0.12.0";
      if (c.name === "b") return "0.10.0";
      return null;
    });
    const rows = await auditVersions(consumers, "0.12.0", fakeFetcher);
    expect(rows).toHaveLength(2);
    expect(rows[0]).toMatchObject({ consumer: "a", driftStatus: "current" });
    expect(rows[1]).toMatchObject({ consumer: "b", driftStatus: "behind_major" });
  });

  it("returns unpinned when fetcher returns null", async () => {
    const consumers: Consumer[] = [
      { name: "a", language: "js", repo: "github:x/a", sdkPinPath: "p", vaultPath: "v", importsSalesforce: true },
    ];
    const rows = await auditVersions(consumers, "0.12.0", async () => null);
    expect(rows[0]?.driftStatus).toBe("unpinned");
  });
});
```

- [ ] **Step 2: Implementation**

`_lib.ts` exports `parseConsumersToml(path)` reading `config/consumers.toml` via `@iarna/toml`.

`audit-versions.ts`:
- `auditVersions(consumers, latest, fetcher)` returns rows.
- `fetchPinFromGitHub(c)` uses `gh api` to read the file at `c.sdkPinPath`, parses out the version (different per language).
- `main()` reads consumers.toml, fetches latest from npm registry (`npm view @devoliveiraeolivi/oli-sdk version`), runs `auditVersions`, prints table.

- [ ] **Step 3: Run + commit**

---

### Task C.2: `smoke-salesforce.{ts,py}` + dispatcher (TDD)

**Files:**
- Create: `scripts/sdk/smoke-salesforce.sh`, `.ts`, `.py`
- Create: `tests/sdk/smoke-salesforce.test.ts`

- [ ] **Step 1: TS impl** — uses `clientFromVault(vaultPath)` from `@devoliveiraeolivi/oli-sdk/salesforce`, runs `await client.describe("Account")`, asserts `name === "Account"`, exits 0/1.

- [ ] **Step 2: Python impl** — same logic via `oli_sdk.salesforce.client_from_vault`.

- [ ] **Step 3: Dispatcher** — `smoke-salesforce.sh --consumer X [--language js|python|both]` reads consumers.toml, picks the right impl, runs it.

- [ ] **Step 4: Tests** — vitest with mocked SDK module asserting describe was called with default `Account`.

- [ ] **Step 5: Commit**

---

## Phase D — Docs + release (Tasks D.1–D.3)

### Task D.1: `docs/SDK-OPS.md` runbook

**Files:**
- Create: `docs/SDK-OPS.md`

Sections:
1. **When to run each script** — onboarding new consumer, rotating tokens, pre-release sanity, drift audit.
2. **Pre-reqs** — env vars, Vault policies (admin token vs ops token), `gh` auth scope.
3. **Examples** — full command lines with expected output.
4. **Troubleshooting** — common errors (Vault path not found, GitHub rate limit, jsforce peerDep missing).
5. **Adding a new consumer** — 5-step procedure: write to consumers.toml, run seed, run smoke, open PR, merge.

- [ ] Commit

---

### Task D.2: CHANGELOG + version bump

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `package.json` (version → 1.3.0)

- [ ] Add `[v1.3.0] — YYYY-MM-DD` entry under `[v1.2.0]`. List the 4 scripts + scope expansion + consumers.toml.

- [ ] Commit

---

### Task D.3: Open PR + tag

- [ ] PR with title `feat: SDK ops toolbox (v1.3.0)` linking to this plan.
- [ ] After CI green + review: merge to main, tag `v1.3.0`, push tag.
- [ ] Verify the existing release workflow still passes (no breaking changes to `.pre-commit-hooks.yaml` or `.github/workflows/security.yml`).

---

## Self-Review Notes

**Spec coverage:** all D1–D10 map to a Task. D1 is documented in A.1 (README/CLAUDE.md updates). D6 is in D.2 (version bump).

**Cross-language consistency:** `smoke-salesforce.ts` and `.py` should produce identical exit codes, identical stderr message format, and identical describe() target (`Account` by default). Documented in `_lib.sh` shared format.

**Bats test count target:** ≥4 cases per shell script. Vitest target: ≥80% line coverage on TS scripts.

**Open question for owner before execution starts:**
- D1 scope expansion: do you want to expand `oli-devops` purpose, or prefer extracting ops scripts to a new `oli-ops-tools` repo? Default of this plan: expand. Reverse cost (later split) is low.
- D4 registry format: TOML chosen for human edit-ability. JSON also viable. No strong preference; flag if any.

---

## Pre-merge gates

- [ ] All tasks complete
- [ ] `bats tests/sdk/*.bats` all pass
- [ ] `vitest run tests/sdk/` all pass
- [ ] Existing security CI still green (no regression)
- [ ] `npm run audit:sdk` runs end-to-end against real GitHub API (smoke test of the script itself)
- [ ] Manual run of `seed-secret.sh` against a Vault dev instance produces expected secret shape
