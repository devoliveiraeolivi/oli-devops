# Adoption Status

Checklist of all OLI repos and their oli-devops baseline status.
Updated as part of each onboarding PR (Step 11 of ONBOARDING.md).

## Phase 1 (in progress)

| Repo | Profile | Baseline version | CI status | Notes |
|---|---|---|---|---|
| oli-gateway | python-docker | — | — | pending (pilot, Plan 2) |
| oli-auth | python-docker | — | — | pending |
| oli-indexer | python-docker | — | — | pending |
| oli-scraper | python-docker | — | — | pending — merge with existing pre-commit |
| oli-ops | js-docker | — | — | pending — first js-docker consumer |

## Phase 2 (planned)

| Repo | Profile | Notes |
|---|---|---|
| oli-scraper-eproc-redesign | python-docker | no CI yet |
| oli-word | python-docker | mixed python+js |
| oli-app | js-docker | no CI yet |
| oli-bi | js-docker | no CI yet |
| psico-sage | js-docker | no CI yet |
| aasp-publicacoes | docker-only | new profile needed |
| serpro-api | docker-only | new profile needed |

## Phase 3+ (backlog)

Python-only repos (no Docker): anp-bi-etl, oli-agent, oli-distribuidoras,
oli-juris, oli-vault. These need a `python-only` profile that uses only
`trivy fs` (no image scan).

Inactive/TBD: salesforce-etl, oli-monitor, oli-prazos, oli-llm, aasp-apex,
split-pdf.

## Legend

- `—` not yet adopted
- `v1.0.0` etc: current pinned version in the repo's `.pre-commit-config.yaml`
- CI status: 🟢 green / 🟡 warn / 🔴 red (as of last update)
