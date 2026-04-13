# oli-devops

Centralized security baseline for OLI repositories.

This repo provides a single source of truth for pre-commit security hooks
and CI security workflows across all OLI projects. Consumer repos reference
pinned versions of this baseline; Renovate propagates updates automatically.

## What's in the box

- **Pre-commit hooks**: `trivy-fs` (vulns + misconfig) and `gitleaks` (secrets)
- **Reusable GitHub Actions workflow**: `trivy image` + `gitleaks` history scan
- **Templates**: drop-in configs per profile (`python-docker`, `js-docker`)
- **Policies**: enforcement matrix, SemVer rules, exceptions format
- **Onboarding procedure**: canonical step-by-step in [docs/ONBOARDING.md](docs/ONBOARDING.md)

## Quick start (consumer repo)

Assuming you already have an OLI repo with a Dockerfile:

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/devoliveiraeolivi/oli-devops
    rev: v1.0.0
    hooks:
      - id: trivy-fs
      - id: gitleaks
```

```yaml
# .github/workflows/ci.yml
jobs:
  security-baseline:
    uses: devoliveiraeolivi/oli-devops/.github/workflows/security.yml@v1.0.0
    with:
      image-name: your-repo-name
```

Full procedure: [docs/ONBOARDING.md](docs/ONBOARDING.md).

## Enforcement matrix (short)

| Check | Pre-commit | CI |
|---|---|---|
| Secrets | 🔴 fail | 🔴 fail |
| Vuln CRITICAL + fix | 🔴 fail | 🔴 fail |
| Vuln CRITICAL no fix | — | 🔴 fail |
| Vuln HIGH + fix | — | 🔴 fail |
| Vuln HIGH no fix | — | 🟡 warn |
| Dockerfile misconfig CRITICAL | 🔴 fail | Phase 2 |

Full matrix and rationale: [policies/ENFORCEMENT.md](policies/ENFORCEMENT.md).

## Versioning

Strict SemVer. Consumers pin exact versions (`rev: v1.0.0`). Renovate
propagates bumps. See [policies/SEMVER.md](policies/SEMVER.md).

## For humans (onboarding a new repo)

Follow [docs/ONBOARDING.md](docs/ONBOARDING.md) step-by-step.

## For AI agents (Claude)

A dedicated skill `adopt-security-baseline` lives at
`skills/adopt-security-baseline/` (added in v1.1.0 after Plan 2 pilot).
The skill reflects the procedure in `docs/ONBOARDING.md`.

## Layout

```
scripts/       # pre-commit hook scripts (trivy-fs.sh, gitleaks-protect.sh)
.github/       # reusable workflow + self-test meta-CI
templates/     # per-profile drop-in files
policies/      # enforcement matrix, SemVer, exceptions format
docs/          # onboarding, troubleshooting, release, adoption status
tests/         # self-test fixtures
skills/        # Claude Code skills (added in v1.1.0)
```

## Contributing

This is an internal OLI baseline. Changes follow the release procedure
in [docs/RELEASE.md](docs/RELEASE.md). Do not merge without:
- Self-test CI green
- CHANGELOG updated
- SemVer decision documented

## License

MIT. See [LICENSE](LICENSE).
