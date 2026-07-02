# Extração do plugin oli-dev → marketplace oli-plugins — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mover o plugin `oli-dev` do `oli-devops` para um marketplace próprio `oli-plugins`, com histórico preservado e versionamento independente, sem janela em que o plugin fique indisponível.

**Architecture:** Big bang em dois repos. Primeiro constrói-se o `oli-plugins` (via `git filter-repo` sobre um clone de `oli-devops@main`), com CI verde e tag `oli-dev-v1.0.0`. Só depois um PR no `oli-devops` remove o plugin. O plugin mantém o path `plugins/oli-dev/`; os design docs são co-localizados sob ele.

**Tech Stack:** git, `git-filter-repo`, GitHub CLI (`gh`), GitHub Actions (shellcheck + suíte sh/dash), Python 3 (validação dos manifestos, já usada pelos testes).

## Global Constraints

- **plugin.json SEM campo `version`** — invariante documentada (pinar obriga bump a cada mudança ou `/plugin update` serve cache velho). `test_manifests.sh:28` asserta isso; NÃO adicionar o campo. Versão vive só na tag/release/CHANGELOG.
- **Layout preservado:** o plugin fica em `plugins/oli-dev/` no repo novo (sem hoist para a raiz). Só os design docs mudam de lugar (para `plugins/oli-dev/docs/superpowers/`).
- **`filter-repo` só em clone fresco** — nunca no checkout de trabalho (reescreve história).
- **Cutover big bang:** nenhuma remoção no `oli-devops` antes do `oli-plugins` estar no ar, verde e taggeado.
- **Owner/base:** `devoliveiraeolivi`; base de instalação = o próprio ecossistema (um dono).
- **Tag por plugin:** `oli-dev-vX.Y.Z` (prefixada), nunca `vX.Y.Z` solta.

---

### Task 1: Criar o repo `oli-plugins` vazio e preparar o clone de migração

**Files:**
- Nenhum arquivo local do `oli-devops` é tocado (operação em repo externo + clone temporário).

**Interfaces:**
- Produces: repo `devoliveiraeolivi/oli-plugins` (vazio, sem commits); diretório de trabalho `../oli-plugins-migration/` (clone fresco de `oli-devops@main`).

- [ ] **Step 1: Garantir git-filter-repo instalado**

Run: `git filter-repo --version`
Expected: imprime a versão (ex.: `git-filter-repo 2.x`). Se `command not found`:
Run: `brew install git-filter-repo` (macOS) ou `pip3 install --user git-filter-repo`
e repita o `--version`.

- [ ] **Step 2: Criar o repo remoto vazio**

Run:
```bash
gh repo create devoliveiraeolivi/oli-plugins --private \
  --description "Marketplace de plugins do ecossistema OLI (Claude Code)."
```
Expected: `✓ Created repository devoliveiraeolivi/oli-plugins`. (Use `--public` se a política do org for repos públicos — confira como está o `oli-devops`.)

- [ ] **Step 3: Clonar o oli-devops (só main) para a migração**

Run:
```bash
cd "$(git -C /Users/cesarbatista/Documents/GitHub/oli-devops rev-parse --show-toplevel)/.."
git clone --single-branch --branch main \
  https://github.com/devoliveiraeolivi/oli-devops.git oli-plugins-migration
```
Expected: clone concluído. `--single-branch --branch main` garante que a branch de trabalho (com este plano e o meta-spec) NÃO entra no clone.

- [ ] **Step 4: Confirmar o conteúdo-fonte no clone**

Run:
```bash
cd ../oli-plugins-migration
test -d plugins/oli-dev && echo "plugin OK"
ls docs/superpowers/specs/*oli-dev* docs/superpowers/plans/*oli-dev* | wc -l   # espera 11
ls docs/superpowers/specs/2026-07-02-oli-plugins-split-design.md 2>/dev/null && echo "META PRESENTE (ruim)" || echo "meta ausente (bom)"
```
Expected: `plugin OK`; `11`; `meta ausente (bom)` (o meta-spec vive só na branch de trabalho, não em main).

---

### Task 2: Extrair o histórico com filter-repo e publicar no oli-plugins

**Files (no clone de migração):**
- Mantém: `plugins/oli-dev/**` (paths inalterados)
- Renomeia: `docs/superpowers/**` → `plugins/oli-dev/docs/superpowers/**`
- Remove: todo o resto (scripts, policies, workflows de segurança, templates, etc.)

**Interfaces:**
- Consumes: clone `../oli-plugins-migration` (Task 1).
- Produces: `oli-plugins@main` com o histórico do plugin (blame preservado) e os 11 docs sob `plugins/oli-dev/docs/superpowers/`.

- [ ] **Step 1: Rodar o filter-repo**

Run (dentro de `../oli-plugins-migration`):
```bash
git filter-repo \
  --path plugins/oli-dev/ \
  --path docs/superpowers/ \
  --path-rename docs/superpowers/:plugins/oli-dev/docs/superpowers/
```
Expected: `Parsed N commits ... Completely finished after ...`. O comando remove `origin` automaticamente.

- [ ] **Step 2: Verificar a árvore resultante**

Run:
```bash
find . -type f -not -path './.git/*' | grep -vE '^\./plugins/oli-dev/' && echo "SOBROU FORA DO PLUGIN (ruim)" || echo "tudo sob plugins/oli-dev (bom)"
test -d plugins/oli-dev/docs/superpowers && echo "docs co-localizados OK"
ls plugins/oli-dev/docs/superpowers/specs/*oli-dev* plugins/oli-dev/docs/superpowers/plans/*oli-dev* | wc -l   # espera 11
```
Expected: `tudo sob plugins/oli-dev (bom)`; `docs co-localizados OK`; `11`.

- [ ] **Step 3: Verificar preservação do histórico (blame)**

Run:
```bash
git log --oneline -- plugins/oli-dev/hooks/branch-state-guard.sh | tail -3
git blame -L 1,5 plugins/oli-dev/tests/run_all.sh | head -1
```
Expected: aparecem commits originais (ex.: os `feat(oli-dev)`/`ci(self-test)` de junho), não um único "import". Blame aponta autoria original.

- [ ] **Step 4: Confirmar que as tags de segurança do oli-devops NÃO vieram**

Run: `git tag`
Expected: **vazio** (as tags `v1.0.0/v1.1.x/v1.2.0` apontavam para commits de segurança, podados pelo filter-repo). Se aparecer alguma, apague: `git tag -d <tag>`.

- [ ] **Step 5: Apontar origin para o oli-plugins e publicar**

Run:
```bash
git remote add origin https://github.com/devoliveiraeolivi/oli-plugins.git
git push -u origin main
```
Expected: `main -> main` criado no `oli-plugins`.

---

### Task 3: Scaffolding do marketplace + fixups do plugin

**Files (no clone de migração, agora = oli-plugins):**
- Create: `.claude-plugin/marketplace.json`
- Create: `README.md` (raiz), `CHANGELOG.md`, `LICENSE`, `policies/SEMVER.md`
- Modify: `plugins/oli-dev/tests/test_manifests.sh:22`
- Modify: `plugins/oli-dev/README.md` (linha de instalação)

**Interfaces:**
- Consumes: `oli-plugins@main` (Task 2).
- Produces: manifesto do marketplace válido (`name: oli-plugins`, registra `oli-dev`); suíte `run_all.sh` passando localmente.

- [ ] **Step 1: Criar `.claude-plugin/marketplace.json`**

```json
{
  "name": "oli-plugins",
  "owner": { "name": "devoliveiraeolivi" },
  "plugins": [
    {
      "name": "oli-dev",
      "source": "./plugins/oli-dev",
      "description": "Maestro do ciclo de desenvolvimento OLI: worktree, brainstorm, review, plano, escrita TDD, review, pre-push gate, PR e finalize."
    }
  ]
}
```

- [ ] **Step 2: Corrigir a asserção de nome no test_manifests.sh**

Modify `plugins/oli-dev/tests/test_manifests.sh` linha 22:
```python
assert mk.get("name") == "oli-plugins", mk.get("name")
```
(Era `== "oli-devops"`. NÃO tocar na linha 28 — `assert "version" not in pj` permanece.)

- [ ] **Step 3: Corrigir o caminho de instalação no README do plugin**

Modify `plugins/oli-dev/README.md`, bloco de Instalação:
```
/plugin marketplace add devoliveiraeolivi/oli-plugins
/plugin install oli-dev
```
(Era `.../oli-devops`.)

- [ ] **Step 4: Criar README raiz do marketplace**

Create `README.md`:
```markdown
# oli-plugins

Marketplace de plugins do ecossistema OLI para Claude Code.

## Plugins

| Plugin | Descrição |
|---|---|
| [oli-dev](plugins/oli-dev/) | Maestro do ciclo de desenvolvimento OLI (worktree → brainstorm → review → plano → TDD → review → pre-push → PR → finalize). |

## Instalação

```
/plugin marketplace add devoliveiraeolivi/oli-plugins
/plugin install oli-dev
```

## Versionamento

Cada plugin versiona de forma independente com tag prefixada (`oli-dev-vX.Y.Z`).
Ver [policies/SEMVER.md](policies/SEMVER.md).
```

- [ ] **Step 5: Criar `policies/SEMVER.md`**

Create `policies/SEMVER.md`:
```markdown
# Versionamento — oli-plugins

Cada plugin versiona **independentemente**. Tag do git é **prefixada por plugin**:
`oli-dev-vMAJOR.MINOR.PATCH` (ex.: `oli-dev-v1.0.0`).

- **MAJOR:** quebra na interface do plugin (flags/sintaxe de comando) ou remoção de fase/gate.
- **MINOR:** nova fase/gate/tier; ou um plugin novo entra no marketplace.
- **PATCH:** correção/documentação sem mudança de comportamento.

O `plugin.json` **não** carrega `version` (pinar obriga bump a cada mudança, ou o
`/plugin update` serve cache velho; sem versão ele segue o SHA — sempre fresco).
A versão canônica é a **tag + GitHub release + seção do CHANGELOG**.

Release do GitHub intitulado `oli-dev vX.Y.Z`, notas = seção do CHANGELOG.
```

- [ ] **Step 6: Criar `CHANGELOG.md`**

Create `CHANGELOG.md`:
```markdown
# Changelog — oli-plugins

Segue [Keep a Changelog](https://keepachangelog.com/) e SemVer por plugin
(ver [policies/SEMVER.md](policies/SEMVER.md)).

## oli-dev

### [oli-dev-v1.0.0] — 2026-07-02

Primeira release do plugin como projeto independente, extraído do `oli-devops`
com histórico preservado. Sem mudança de comportamento em relação ao último
estado no `oli-devops`.

- Maestro do ciclo de desenvolvimento OLI: worktree → brainstorm → review staff
  cético → plano → escrita TDD por subagente (tier full/light) → code-review/
  simplify/verify (+security-review condicional) → pre-push gate → PR → finalize.
- Instalação via `/plugin marketplace add devoliveiraeolivi/oli-plugins`.
```

- [ ] **Step 7: Copiar a LICENSE do oli-devops**

Run:
```bash
cp /Users/cesarbatista/Documents/GitHub/oli-devops/LICENSE ./LICENSE
```
Expected: `LICENSE` presente na raiz.

- [ ] **Step 8: Rodar a suíte do plugin localmente**

Run: `sh plugins/oli-dev/tests/run_all.sh`
Expected: termina em `ALL GREEN`. O `test_manifests` agora valida `name == "oli-plugins"` e segue exigindo `"version" not in pj`.

- [ ] **Step 9: Commit**

```bash
git add .claude-plugin/marketplace.json README.md CHANGELOG.md LICENSE policies/SEMVER.md \
        plugins/oli-dev/tests/test_manifests.sh plugins/oli-dev/README.md
git commit -m "chore(oli-plugins): scaffolding do marketplace + fixups pós-extração

- marketplace.json (name oli-plugins, registra oli-dev)
- README raiz, CHANGELOG, LICENSE, policies/SEMVER (tag por plugin)
- test_manifests: name assertion oli-devops -> oli-plugins (version-less mantido)
- README do plugin: install path -> oli-plugins"
git push
```

---

### Task 4: CI do oli-plugins (shellcheck + suíte) verde

**Files:**
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: `oli-plugins@main` com a suíte passando localmente (Task 3).
- Produces: workflow `ci` verde no push — gate para a tag da Task 5.

- [ ] **Step 1: Criar `.github/workflows/ci.yml`**

```yaml
name: ci

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: ${{ github.ref != 'refs/heads/main' }}

jobs:
  shellcheck:
    name: Shellcheck (hooks + testes)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@df4cb1c069e1874edd31b4311f1884172cec0e10 # v6.0.3
      - name: Run shellcheck
        run: |
          sudo apt-get update -qq
          sudo apt-get install -qq shellcheck
          shellcheck plugins/oli-dev/hooks/*.sh plugins/oli-dev/tests/*.sh

  plugin-tests:
    name: Suíte do plugin (dash + GNU sed)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@df4cb1c069e1874edd31b4311f1884172cec0e10 # v6.0.3
      - name: Run plugin suite
        # Ubuntu: /bin/sh = dash e sed = GNU — eixo de portabilidade que o macOS local não cobre.
        run: sh plugins/oli-dev/tests/run_all.sh
```
(SHA do checkout copiado do `self-test.yml` do oli-devops — pin imutável, mesma política de supply chain.)

- [ ] **Step 2: Commit e push**

```bash
git add .github/workflows/ci.yml
git commit -m "ci(oli-plugins): shellcheck + suíte do plugin (dash + GNU sed)"
git push
```

- [ ] **Step 3: Verificar CI verde**

Run: `gh run list -R devoliveiraeolivi/oli-plugins --workflow ci.yml -L 1 --json status,conclusion --jq '.[0].status + " " + (.[0].conclusion // "-")'`
Expected: `completed success` (aguarde se `in_progress`).

---

### Task 5: Tag `oli-dev-v1.0.0` + GitHub release

**Interfaces:**
- Consumes: CI verde (Task 4).
- Produces: tag `oli-dev-v1.0.0` e release publicados no `oli-plugins`.

- [ ] **Step 1: Confirmar CI verde no commit a ser taggeado**

Run: `gh run list -R devoliveiraeolivi/oli-plugins --branch main -L 1 --json headSha,conclusion --jq '.[0].headSha[0:7] + " " + (.[0].conclusion // "-")'`
Expected: `<sha> success`, e `<sha>` = `git rev-parse --short main`.

- [ ] **Step 2: Criar a tag anotada e empurrar**

Run (dentro de `../oli-plugins-migration`):
```bash
git tag -a oli-dev-v1.0.0 -m "oli-dev v1.0.0"
git push origin oli-dev-v1.0.0
```
Expected: `oli-dev-v1.0.0 -> oli-dev-v1.0.0`.

- [ ] **Step 3: Criar o GitHub release com as notas do CHANGELOG**

Run:
```bash
gh release create oli-dev-v1.0.0 -R devoliveiraeolivi/oli-plugins \
  --title "oli-dev v1.0.0" \
  --notes-file <(sed -n '/### \[oli-dev-v1.0.0\]/,/^## \|^### \[/p' CHANGELOG.md | sed '$d')
```
Expected: URL do release impressa.

---

### Task 6: Smoke test da instalação (verificação manual)

**Interfaces:**
- Consumes: release publicado (Task 5).
- Produces: confirmação de que o plugin instala e roda a partir do marketplace novo.

- [ ] **Step 1: Adicionar o marketplace e instalar (numa sessão interativa do Claude Code)**

Run (no Claude Code, não no shell):
```
/plugin marketplace add devoliveiraeolivi/oli-plugins
/plugin install oli-dev
```
Expected: marketplace listado com `oli-dev`; instalação sem erro.

- [ ] **Step 2: Verificar que o comando existe**

Run (no Claude Code): `/oli-dev` (sem args, ou com uma ideia trivial para ver a Fase 0 verificar Opus)
Expected: a skill `dev-cycle` inicia (ou avisa dependência do superpowers) — prova que comando/skill/hooks carregaram do repo novo.

- [ ] **Step 3: Registrar o resultado**

Anote no PR de remoção (Task 7) que o smoke test passou (data + o que foi verificado). É o gate para prosseguir com a remoção.

---

### Task 7: PR de remoção no oli-devops

**Files (branch `chore/extract-oli-dev-plugin` do oli-devops — já tem o spec + este plano):**
- Delete: `plugins/oli-dev/**`, `.claude-plugin/marketplace.json`, os 11 `docs/superpowers/{specs,plans}/*oli-dev*`
- Modify: `.github/workflows/self-test.yml` (remove shellcheck do plugin + job `plugin-tests`)
- Modify: `README.md` (ponteiro), `CHANGELOG.md` (entrada)

**Interfaces:**
- Consumes: smoke test OK (Task 6).
- Produces: `oli-devops` sem o plugin, self-test de segurança verde.

- [ ] **Step 1: Voltar ao checkout do oli-devops e à branch de trabalho**

Run:
```bash
cd /Users/cesarbatista/Documents/GitHub/oli-devops
git checkout chore/extract-oli-dev-plugin
```
Expected: na branch que já contém o spec (2189989) e este plano.

- [ ] **Step 2: Remover a árvore do plugin, o marketplace e os docs do plugin**

Run:
```bash
git rm -r plugins/oli-dev
git rm .claude-plugin/marketplace.json
git rm docs/superpowers/specs/*oli-dev* docs/superpowers/plans/*oli-dev*
rmdir .claude-plugin 2>/dev/null || true
```
Expected: arquivos staged para remoção. (O meta-spec `2026-07-02-oli-plugins-split-design.md` e este plano NÃO casam com `*oli-dev*` → permanecem.)

- [ ] **Step 3: Remover os jobs do plugin do self-test.yml**

Modify `.github/workflows/self-test.yml`: no job `shellcheck`, apagar o comentário e a linha do plugin (deixando só `scripts/*.sh`):
```yaml
      - name: Run shellcheck
        run: |
          sudo apt-get update -qq
          sudo apt-get install -qq shellcheck
          shellcheck -x --source-path=scripts scripts/*.sh
```
E apagar o job `plugin-tests` inteiro (o bloco `plugin-tests:` … `run: sh plugins/oli-dev/tests/run_all.sh`).

- [ ] **Step 4: Adicionar o ponteiro no README do oli-devops**

Modify `README.md` — adicionar seção curta (perto do topo ou numa seção "Plugins"):
```markdown
## Plugin de fluxo de desenvolvimento

O plugin `oli-dev` (maestro do ciclo de dev) **mudou-se** para o marketplace
próprio [`devoliveiraeolivi/oli-plugins`](https://github.com/devoliveiraeolivi/oli-plugins):

```
/plugin marketplace add devoliveiraeolivi/oli-plugins
/plugin install oli-dev
```
```

- [ ] **Step 5: Adicionar entrada no CHANGELOG do oli-devops**

Modify `CHANGELOG.md`, sob `## [Unreleased]`:
```markdown
### Removed

- **Plugin `oli-dev` extraído para o marketplace `devoliveiraeolivi/oli-plugins`**
  (histórico preservado via `git filter-repo`). Saem deste repo: `plugins/oli-dev/`,
  `.claude-plugin/marketplace.json`, os design docs `docs/superpowers/*oli-dev*`, e os
  jobs `plugin-tests`/shellcheck-do-plugin do `self-test.yml`. Instalação agora via
  `/plugin marketplace add devoliveiraeolivi/oli-plugins`. Desacopla as duas cadências
  (o self-test de segurança não depende mais dos testes do plugin) e para de poluir os
  releases de segurança com mudanças do plugin. Ver `docs/superpowers/specs/2026-07-02-oli-plugins-split-design.md`.
```

- [ ] **Step 6: Validar o self-test localmente (o que dá) e commitar**

Run:
```bash
shellcheck -x --source-path=scripts scripts/*.sh && echo "shellcheck scripts OK"
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/self-test.yml')); print('self-test.yml YAML OK')"
git add -A
git commit -m "chore(split): remove o plugin oli-dev (movido para oli-plugins)

Cutover big bang: o oli-plugins já está no ar, verde e taggeado (oli-dev-v1.0.0).
Remove plugins/oli-dev, marketplace.json, os 11 docs *oli-dev*, e os jobs do
plugin no self-test. Ponteiro no README + entrada no CHANGELOG. Self-test de
segurança (scripts/yamllint/schema/fixtures) intacto."
git push
```
Expected: `shellcheck scripts OK`; `self-test.yml YAML OK`; push conclui.

---

### Task 8: PR, self-test verde e merge

**Interfaces:**
- Consumes: branch `chore/extract-oli-dev-plugin` com o spec + plano + remoção (Task 7).
- Produces: `oli-devops@main` sem o plugin, self-test verde.

- [ ] **Step 1: Abrir o PR**

Run:
```bash
gh pr create --base main --title "chore(split): extrai o plugin oli-dev para o marketplace oli-plugins" \
  --body "Spec + plano + remoção do plugin. O oli-plugins já está no ar (tag oli-dev-v1.0.0), smoke test de instalação OK. Desacopla as cadências e limpa os releases de segurança. Ver docs/superpowers/specs/2026-07-02-oli-plugins-split-design.md."
```
Expected: URL do PR.

- [ ] **Step 2: Aguardar o self-test verde no PR**

Run: `gh pr checks --watch` (ou poll `gh pr checks`)
Expected: todos os jobs de segurança verdes; os jobs `plugin-tests`/shellcheck-do-plugin **não existem mais** (removidos).

- [ ] **Step 3: Merge**

Run: `gh pr merge --squash`
Expected: PR mergeado.

- [ ] **Step 4: Verificação final (DoD)**

Run:
```bash
git checkout main && git pull --ff-only
test -d plugins/oli-dev && echo "AINDA TEM PLUGIN (ruim)" || echo "plugin removido (bom)"
gh run list -R devoliveiraeolivi/oli-devops --workflow self-test.yml --branch main -L 1 --json conclusion --jq '.[0].conclusion'
```
Expected: `plugin removido (bom)`; self-test `success`.

- [ ] **Step 5: Limpar o clone de migração**

Run: `rm -rf ../oli-plugins-migration`
Expected: diretório temporário removido.

---

## Self-Review (writing-plans)

**Cobertura do spec:** ✅ repo novo (T1-T2), layout+docs co-localizados (T2), scaffolding+SEMVER (T3), fixups test_manifests/README (T3), version-less mantido (Global Constraints + T3 Step 2), CI (T4), tag por plugin (T5), smoke test (T6), cleanup oli-devops (T7), DoD/merge (T8).

**Placeholders:** nenhum — todo conteúdo (JSON, YAML, edits, comandos) está inline.

**Consistência de tipos/nomes:** `oli-plugins` (marketplace name) e `oli-dev-v1.0.0` (tag) usados de forma idêntica em T3/T4/T5/T7. `plugins/oli-dev/` preservado em toda parte. `plugin.json` sem `version` reforçado nas Global Constraints, T3 e no fixup de T7 (o meta-spec e este plano não casam `*oli-dev*`, então sobrevivem à remoção).
