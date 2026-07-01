# Changelog

All notable changes to oli-devops are documented here. Follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project
follows strict [SemVer](policies/SEMVER.md).

## [Unreleased]

### Fixed

- **`plugins/oli-dev/tests/`**: `test_manifests.sh` and `test_evals.sh` now detect the
  Python interpreter portably (`python3`, falling back to `python`) instead of assuming a
  bare `python` exists. Fixes spurious `python: command not found` suite failures on modern
  macOS, where only `python3` is present.

## [v1.1.1] — 2026-05-08

### Fixed

- **`security.yml` reusable workflow**: granted `pull-requests: read` to the
  workflow's `permissions:` block. Without it, `gitleaks-action@v2` failed
  with HTTP 403 on `pull_request` events (it lists PR commits via
  `GET /repos/{owner}/{repo}/pulls/{n}/commits`, which requires
  `pull-requests: read`). Discovered on `oli-etl` PR #4.
- **`security.yml` comment**: corrected misleading comment that claimed callers
  could elevate the workflow's permissions. The `permissions:` block of a
  reusable workflow is a hard cap — callers cannot extend it.

## [v1.1.0] — 2026-05-05

### Added

- **python-only profile** (`templates/python-only/`): for Python repos without a
  Dockerfile. Runs `trivy-fs` + `gitleaks` pre-commit hooks; CI layer is gitleaks
  history scan only (no image build/scan). Unblocks: `oli-vault`, `anp-bi-etl`.
- **`ci-security-standalone.yml`** template for all profiles: complete standalone
  GitHub Actions workflow for repos with no existing `ci.yml`. Targets all Grupo A/B
  consumer repos (oli-gateway, oli-auth, oli-ops, etc.).
- **`security.yml` optional `image-name` input**: `trivy-image` job is now
  conditionally skipped when `image-name` is not provided. Fully backward-compatible.
- **`policies/org-ruleset.json`**: org-level branch ruleset for all `oli-*` repos
  (enforcement: evaluate until all repos onboarded).
- **`.github/workflows/audit-adoption.yml`**: weekly audit workflow that opens/
  updates a GitHub issue listing adoption gaps across the org.

### Fixed

- **Node.js 24 migration** (`security.yml`, `self-test.yml`): bumped all actions
  to versions that run on Node.js 24 — required before GitHub's forced migration
  on 2026-06-02 (`actions/checkout@v6`, `actions/setup-python@v6`,
  `docker/setup-buildx-action@v4`, `aquasecurity/trivy-action@0.36.0`).
  Consumer repos pinned to `@v1.0.0` should upgrade to `@v1.1.0` to eliminate
  the deprecation warnings.
- **`trivy-action` tag format** (`security.yml`): corrected invalid tag `0.36.0`
  to `v0.36.0`.

### Migration

No breaking changes. Existing consumers pinned to `v1.0.0` are unaffected.
Update to `v1.1.0` to access the new python-only profile or standalone CI template.

## [v1.0.0] - 2026-04-13

Initial release. Establishes the security baseline for OLI repos.

### Added
- `.pre-commit-hooks.yaml` exposing `trivy-fs` and `gitleaks` hooks
- `scripts/common.sh` with shared utilities (tool versions, docker detection,
  include guard, Windows path translation)
- `scripts/trivy-fs.sh`: Trivy filesystem scan via Docker with local binary fallback
  - Policy: CRITICAL severity, `--ignore-unfixed`, scanners `vuln,secret,misconfig`
- `scripts/gitleaks-protect.sh`: Gitleaks staged-files scan via Docker
  (`ghcr.io/gitleaks/gitleaks`, read-only mount) with local binary fallback
- `.github/workflows/security.yml`: reusable workflow (`workflow_call`)
  - `trivy image` scan with HIGH+CRITICAL / fixed → fail, unfixed → warn
  - `gitleaks` full history scan
  - Explicit `permissions: contents: read` for least-privilege default
- `.github/workflows/self-test.yml`: meta-CI validating scripts + fixtures on
  every push (7 jobs: shellcheck, yamllint, schema, 2x trivy, 2x gitleaks)
- `tests/fixtures/`: clean, with-secret (non-allowlisted AKIA),
  with-critical-cve (pyyaml 5.3.1 + requirements.txt lockfile)
- `templates/python-docker/` and `templates/js-docker/`: drop-in configs
  - `pre-commit-config.yaml`
  - `ci-security-job.yml`
  - `renovate.json`
  - `claude-md-section.md`
- `policies/ENFORCEMENT.md`: the matrix (pre-commit vs CI per severity)
- `policies/SEMVER.md`: strict versioning rules
- `policies/EXCEPTIONS.md`: mandatory suppression format
- `docs/ONBOARDING.md`: canonical step-by-step procedure
- `docs/TROUBLESHOOTING.md`: common issues and fixes
- `docs/RELEASE.md`: release procedure
- `docs/ADOPTION-STATUS.md`: consumer tracking
- `CLAUDE.md`: AI assistant guide
- `README.md`: human overview

### Tool versions pinned
- Trivy: `0.69.3`
- Gitleaks: `8.30.1`

### Not in this release (Phase 2)
- `adopt-security-baseline` Claude Code skill (added in v1.1.0 after pilot in Plan 2)
- Misconfig scanning in CI layer (currently pre-commit only)
- `suppression-format-check` hook
- SBOM generation
- `python-only` and `docker-only` profiles
