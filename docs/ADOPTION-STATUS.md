# Adoption Status

Checklist of all OLI repos and their oli-devops baseline status.
Updated as part of each onboarding PR (Step 11 of ONBOARDING.md).

> **Ground-truth pass 2026-07-02.** The Phase 1 table below was rebuilt by
> reading each repo's actual `.pre-commit-config.yaml` and workflows via `gh`,
> not from onboarding-PR memory. It had drifted badly: every row showed
> `pending` while 6 of 8 repos were in fact already consuming the baseline and
> green. Two callouts came out of that pass — see **Propagation gaps** below.

## Phase 1

`CI @` = version in the reusable-workflow pin (`security.yml@`).
`pre-commit @` = `rev:` in `.pre-commit-config.yaml`. They differ per repo
because only one of the two is auto-bumped today (see Propagation gaps).

| Repo | Profile | pre-commit @ | CI @ | CI status | Notes |
|---|---|---|---|---|---|
| oli-gateway | python-docker | v1.1.1 | v1.1.1 | 🟢 (main, 07-02) | adopted, both layers; `security-baseline` is a **job inside `ci.yml`**, not a standalone file |
| oli-auth | python-docker | **v1.0.0** ⚠️ | v1.1.1 | 🟢 | adopted; pre-commit pin ~3 months stale |
| oli-indexer | python-docker | — | — | — | **not adopted** — runs its own inline `security:` job (Bandit). Migration, not greenfield |
| oli-scraper | python-docker | **v1.0.0** ⚠️ | v1.1.1 | PR/schedule only | adopted; pre-commit pin ~3 months stale |
| oli-ops | js-docker | v1.1.1 | v1.1.1 | 🟢 | adopted; first js-docker consumer |
| oli-vault | python-only | — | — | — | **not adopted** — greenfield, default branch `master`, no workflows yet |
| anp-bi-etl | python-only | **v1.1.0** ⚠️ | v1.1.1 | 🟢 | adopted; pre-commit pin stale |
| oli-etl | python-docker | — (CI only) | v1.1.1 | 🟢 | adopted early, outside the original plan; CI layer only, no pre-commit block |

## Propagation gaps (found 2026-07-02)

1. **Every adopted repo pins `security.yml@v1.1.1`, which carries
   `gitleaks-action@v2`.** Node 20 leaves GitHub-hosted runners on
   **2026-09-16** → those CI jobs break. `v1.2.0` moves it to v3; the
   `github-actions` Renovate manager should open the bump PRs automatically
   (delayed by each repo's `minimumReleaseAge`). **Verify the PRs land by
   ~2026-07-10; if not, bump manually. Hard deadline 2026-09-16.**
2. **Pre-commit `rev:` pins are NOT auto-bumped.** Renovate's `pre-commit`
   manager is [disabled by default](https://docs.renovatebot.com/modules/manager/pre-commit/)
   and the template `renovate.json` never opted in — so the `rev:` pins have
   sat at their onboarding version for months (auth/scraper still on v1.0.0)
   while the CI pin moved. The template is fixed as of the PR that added this
   note; **existing consumers still need their own `renovate.json` patched**
   (add `"pre-commit": {"enabled": true}`) or a one-off manual bump.

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
| oli-monitor | gitleaks-only (ad-hoc) | compose/pre-built stack — no buildable image, no lang manifest; only gitleaks applies |

## Phase 3+ (backlog)

Python-only repos (no Docker): anp-bi-etl, oli-agent, oli-distribuidoras,
oli-juris. Profile `python-only` now available (v1.1.0) — see Phase 1 above
for oli-vault onboarding.

Inactive/TBD: salesforce-etl, oli-prazos, oli-llm, aasp-apex, split-pdf.

## Legend

- `—` layer not present in that repo
- `v1.0.0` etc: exact version pinned in that layer, read from the repo on the
  ground-truth date
- ⚠️ pin is behind the latest release (stale)
- CI status: 🟢 green / 🟡 warn / 🔴 red as of last verification; "PR/schedule
  only" = the security workflow has no `push:main` trigger, so there is no
  main-branch run to color (by design — see ONBOARDING.md Step 5)
