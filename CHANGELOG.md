# Changelog

All notable changes to oli-devops are documented here. Follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project
follows strict [SemVer](policies/SEMVER.md).

## [Unreleased]

### Changed

- **`oli-dev` review gates — princípio "evidência ou abstenha"** (`references/review-gates.md`): bloco
  inviolável no topo, valendo p/ staff-reviewer (Fase 2), gates da Fase 5 e conductor. Todo achado
  exige evidência citada (`file:line`/output); proibido asserir de memória/doc desatualizado;
  `⚠️ não verificado` é saída obrigatória; conductor adjudica com evidência, não por deferência.
  Fecha o buraco de reviewer que "afirma sem checar" e lava palpite em fato revisado.
- **Padrão de trigger dos templates de segurança** (`templates/*/ci-security-standalone.yml`): de
  `push:main + pull_request` para `pull_request` + `schedule` semanal + `workflow_dispatch`, com
  `concurrency: cancel-in-progress`. Remove o re-run do scan Trivy no `push:main` (era re-run puro
  do que o PR já escaneou, dado mantenedor solo + merges em série); o `schedule` semanal cobre CVE
  nova divulgada contra um main que não mudou — o único caso que o gatilho só-PR perderia. Novos
  adotantes nascem com o padrão certo; consumers existentes só herdam ao re-copiar o template.
- **`docs/ONBOARDING.md` § Step 5**: nova subseção "Padrão de trigger (custo de Actions)" —
  documenta CI só-no-PR, build em workflow próprio no `push:main` (sem re-gate), `concurrency`, e o
  anti-padrão de branches efêmeras (`claude/**`, `feat/*`) no `push:` (double-run). Referencia
  oli-gateway (split) e oli-indexer #355.
- **`oli-dev` pre-push gate prefere `scripts/check.sh`**: o gate da Fase 6 e o backstop
  `hooks/pre-push-gate.sh` agora rodam `scripts/check.sh --fast` do repo quando existe (fonte
  única espelhando o CI). Fallback (sem check.sh) enxuto: `ruff check` + `ruff format --check` +
  `mypy` baseline-aware — sem `black` (legado) e sem `pytest` (já roda no `verify` da Fase 5).
  Corrige falso-bloqueio do mypy baseline e o double-run com o `.githooks/pre-push` do repo.
  Override `OLI_DEV_*_CMDS` ainda vence. Node inalterado.

### Added

- **`oli-dev` tier de modelo `light`** (`/oli-dev light <ideia>`): os escritores TDD (Fase 4) e o
  staff-reviewer (Fase 2) rodam em **Sonnet 4.6** em vez de Opus, para ganho de custo/latência. O
  default (`full` / sem token) continua idêntico (tudo Opus). Conductor sempre Opus; `/code-review`,
  `/simplify`, `verify`, `/security-review` inalterados. Fonte única em
  `plugins/oli-dev/skills/dev-cycle/references/model-tiers.md`.

### Changed

- **`oli-dev` "Princípio 4" redefinido**: de *"todo subagente em Opus"* para *"conductor sempre
  Opus; os dois papéis despachados (escritores TDD + staff-reviewer) seguem o tier"*. `/oli-dev
  <ideia>` sem token continua full-Opus (comportamento anterior). O parsing de `finalize` passou a
  ser match exato (antes era "começa com").

### Fixed

- **`plugins/oli-dev/tests/`**: `test_manifests.sh` and `test_evals.sh` now detect the
  Python interpreter portably (`python3`, falling back to `python`) instead of assuming a
  bare `python` exists. Fixes spurious `python: command not found` suite failures on modern
  macOS, where only `python3` is present.
- **`.gitignore`**: also ignore `.claude/worktrees/` (the location the native `EnterWorktree`
  tool uses), not just the manual-fallback `.worktrees/`. Prevents the worktree from polluting
  `git status` / being accidentally committed on the main checkout.

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
