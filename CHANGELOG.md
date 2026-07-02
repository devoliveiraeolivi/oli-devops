# Changelog

All notable changes to oli-devops are documented here. Follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project
follows strict [SemVer](policies/SEMVER.md).

## [Unreleased]

### Security

- **Actions de terceiros pinadas por SHA** em `security.yml` e `self-test.yml` (versão anotada em
  comentário ao lado de cada pin). Motivação: incidente supply-chain do ecossistema Trivy em
  2026-03 — release maliciosa `v0.69.4` (janela de ~3h), imagens `aquasec/trivy:0.69.5/0.69.6`
  com C2 embutido (removidas do Docker Hub) e **todas as tags 0.0.1–0.34.2 da `trivy-action`
  comprometidas**. O pin vigente (`trivy-action@v0.36.0`, 2026-04-22) foi verificado como
  pós-incidente e seguro; o SHA elimina a classe de ataque por tag mutável.
- **Imagens docker dos hooks pinadas por digest** (`aquasec/trivy` e `ghcr.io/gitleaks/gitleaks`
  via `tag@sha256:...` em `scripts/common.sh`): tag de registry é mutável — o mesmo incidente
  publicou imagens maliciosas sob tags novas. One-liners de refresh documentados no próprio
  `common.sh`; passo novo no procedimento de bump do `CLAUDE.md`.

### Changed

- **Trivy 0.69.3 → 0.72.0** (`scripts/common.sh`): bump deliberado após verificação do incidente
  acima (0.70.0+ são pós-resolução; latest 0.72.0 de 2026-06-30). Scanner mais novo pode trazer
  detecções novas → próximo release é **MINOR** per `policies/SEMVER.md`. Fixtures validadas
  pelo self-test CI (runner local sem docker/trivy).
- **`gitleaks protect --staged` → `gitleaks git --pre-commit --staged`**
  (`scripts/gitleaks-protect.sh` + descrição do hook em `.pre-commit-hooks.yaml`): `protect` está
  deprecated desde a 8.19.0 (oculto do `--help`); o comando novo espelha o hook pre-commit oficial
  do gitleaks. Mesmo engine e mesma detecção na 8.30.1 pinada. Binário **local** < 8.19.0 agora
  cai para a imagem docker pinada com aviso, em vez de quebrar no subcomando inexistente.
- **`oli-dev` condutor realinhado à prática e podado de duplicação com o superpowers**:
  `setup-gate.md` prefere o **EnterWorktree nativo** (`.claude/worktrees/`) com
  `using-git-worktrees` como fallback (dep exigida só nesse caminho; gitignore do path usado);
  `finalize.md` delega a mecânica de remoção de worktree a `finishing-a-development-branch`, mas
  MANTÉM o caveat Windows/junction (verificado: a skill do superpowers NÃO o cobre) e o "nunca
  pasta irmã do repo" no `setup-gate.md`; mensagem informativa do `branch-state-guard.sh` fica
  agnóstica de local. Gates OLI (da main, MERGED antes de deletar, close-out) intactos.
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
- **`oli-dev` "Princípio 4" redefinido**: de *"todo subagente em Opus"* para *"conductor sempre
  Opus; os dois papéis despachados (escritores TDD + staff-reviewer) seguem o tier"*. `/oli-dev
  <ideia>` sem token continua full-Opus (comportamento anterior). O parsing de `finalize` passou a
  ser match exato (antes era "começa com").

### Added

- **`self-test.yml`: cobertura de CI para o plugin oli-dev** — job `shellcheck` passa a lintar
  `plugins/oli-dev/{hooks,tests}/*.sh`, e novo job `plugin-tests` roda a suíte no ubuntu
  (`/bin/sh` = dash + GNU sed): é o eixo de ambiente que o macOS local não cobre e por onde as
  3 fugas históricas de portabilidade escaparam. A suíte do plugin deixa de ser local-only.
- **`oli-dev` testes: matriz de shells nos testes de hook** (`OLI_DEV_TEST_SHELL`): os helpers
  `gate_rc`/`gate_err` passam a invocar o hook com o shell da matriz ({`sh`, `dash`}, via
  `run_all.sh`, skip anunciado se ausente) — o hook é exercitado sob cada shell, não o arquivo
  de teste. `run_all.sh` decide a matriz por **introspecção** (teste entra se consome
  `OLI_DEV_TEST_SHELL` — fonte única, sem whitelist paralela) e um **meta-assert** em
  `test_manifests.sh` falha se algum teste com `gate_rc()` deixar de consumir a env-var (trava a
  reversão silenciosa da matriz). Feedback local rápido p/ a classe de bugs de portabilidade-sh
  (3 fugas históricas).
  Novo `tests/test_shellcheck.sh` (skip anunciado sem shellcheck local) linta `hooks/*.sh` +
  `tests/*.sh`; achados pré-existentes nos testes zerados via diretivas justificadas (SC2015/SC2069).
- **`oli-dev` tier de modelo `light`** (`/oli-dev light <ideia>`): os escritores TDD (Fase 4) e o
  staff-reviewer (Fase 2) rodam em **Sonnet 4.6** em vez de Opus, para ganho de custo/latência. O
  default (`full` / sem token) continua idêntico (tudo Opus). Conductor sempre Opus; `/code-review`,
  `/simplify`, `verify`, `/security-review` inalterados. Fonte única em
  `plugins/oli-dev/skills/dev-cycle/references/model-tiers.md`.

### Fixed

- **`security.yml`: `gitleaks-action` v2 → v3.0.0** (SHA-pinado): a v2 roda em Node 20, que
  deixou de ser o default dos runners em **2026-06-02** (v2 já exige env var de opt-out) e será
  **removido em 2026-09-16** — a partir daí a v2 para de funcionar. v3 = mesmo comportamento,
  runtime Node 24. **Consumers pinados em ≤ v1.1.1 carregam a v2 e precisam subir para o próximo
  release antes de 2026-09-16.**
- **Templates re-pinados para `v1.1.1`** (`rev:` do `pre-commit-config.yaml`, `@vX.Y.Z` dos
  `ci-security-*.yml` e `claude-md-section.md` — estavam em v1.0.0/v1.1.0): novos adotantes
  copiavam um baseline com o bug do 403 do gitleaks já corrigido na v1.1.1. Novo item no
  checklist de prerequisites do `RELEASE.md` trava a recorrência a cada release.
- **`docs/ADOPTION-STATUS.md`: registra `oli-etl`** — adotou a camada CI cedo
  (`security-baseline.yml` → `security.yml@v1.1.1`, verificado em 2026-07-02), mas não constava
  na tabela (a v1.1.1 foi inclusive descoberta no PR #4 dele). Doc e realidade divergiam.

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
