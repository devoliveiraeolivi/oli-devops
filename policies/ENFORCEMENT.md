# Enforcement Policy

This document is the source of truth for how oli-devops decides what to block
vs warn vs ignore. It is referenced from the spec, from consumer CLAUDE.md
files, and from the scripts themselves.

## The Matrix

| Check | Pre-commit (local, `trivy fs`) | CI (main/PR, `trivy image`) |
|---|---|---|
| Secrets (gitleaks) | 🔴 fail (precision ~99%) | 🔴 fail |
| Vuln CRITICAL **with fix available** | 🔴 fail | 🔴 fail |
| Vuln CRITICAL **without fix** | — (ignored) | 🔴 fail |
| Vuln HIGH **with fix** | — (ignored) | 🔴 fail |
| Vuln HIGH **without fix** | — (ignored) | 🟡 warn |
| Vuln MEDIUM/LOW | — | — |
| Dockerfile misconfig CRITICAL | 🔴 fail | — (Phase 2) |
| Dockerfile misconfig HIGH/MEDIUM | — | — (Phase 2) |

## Rationale

**Pre-commit blocks only:**
1. Secrets (gitleaks) — ~99% precision, and leaks are irreversible
2. Vuln CRITICAL with fix available — high severity AND acting now is possible
3. Dockerfile misconfig CRITICAL — rare but catastrophic (ex: exposed socket)

All HIGH and all "unfixed" findings are **ignored at pre-commit** to avoid
false-positive fatigue. The CI layer catches them later with more context.

**CI is stricter because:**
- Devs can resolve in a PR with time to investigate
- CI runs on PRs, not on every interactive commit — noise is acceptable
- CI is the authoritative gate before merge

**Why "HIGH without fix" is only warn in CI:**
There is no action the dev can take. Blocking teaches the team to ignore the
scanner. Warning keeps it visible via PR annotations without blocking merges.

## How the policy is encoded in code

### Pre-commit (`scripts/trivy-fs.sh`)
```bash
trivy fs --scanners vuln,secret,misconfig \
         --severity CRITICAL \
         --ignore-unfixed \
         --exit-code 1
```

### CI (`.github/workflows/security.yml`)
```yaml
# Step 1: fail on fixed HIGH/CRITICAL
- uses: aquasecurity/trivy-action@0.28.0
  with:
    severity: "HIGH,CRITICAL"
    ignore-unfixed: true
    exit-code: "1"

# Step 2: warn on unfixed HIGH/CRITICAL
- uses: aquasecurity/trivy-action@0.28.0
  with:
    severity: "HIGH,CRITICAL"
    ignore-unfixed: false
    exit-code: "0"
```

## Changing the matrix

This is a breaking change for consumers. Requires:
1. MAJOR version bump (see [SEMVER.md](SEMVER.md))
2. Migration section in [CHANGELOG.md](../CHANGELOG.md)
3. Explicit diff of the matrix in the PR description
4. Consumer PRs to re-pin and handle any new failures

Do not "tighten quietly" — tightening without ceremony breaks consumer trust
and encourages `--no-verify` habits.
