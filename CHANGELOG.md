# Changelog

All notable changes to oli-devops are documented here. Follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project
follows strict [SemVer](policies/SEMVER.md).

## [Unreleased]

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
