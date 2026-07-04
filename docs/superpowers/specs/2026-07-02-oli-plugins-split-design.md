# Spec — Extração do plugin oli-dev para o marketplace `oli-plugins`

- **Data:** 2026-07-02
- **Status:** design aprovado (brainstorming), aguardando plano de implementação
- **Repos afetados:** `devoliveiraeolivi/oli-devops` (origem), `devoliveiraeolivi/oli-plugins` (novo)

## Contexto e motivação

O plugin `oli-dev` (maestro do ciclo de desenvolvimento OLI) vive dentro do
`oli-devops`, que é o **baseline de segurança** consumido por ~15 repos. São dois
produtos sem código em comum, co-localizados por conveniência. Evidência do
acoplamento problemático (medida em 2026-07-02):

- **Código disjunto.** O plugin não toca `scripts/`, `policies/`, nem os workflows
  de segurança; o baseline não toca `plugins/oli-dev/`.
- **Públicos distintos.** Baseline: consumers que pinam `security.yml@vX` e copiam
  templates. Plugin: desenvolvedores que rodam `/plugin install oli-dev`.
- **Cadências distintas, plugin mais quente.** 34 de 93 commits tocam o plugin; a
  maioria dos ~20 commits recentes é plugin-only.
- **Poluição de versão (pior sintoma).** O plugin **não tem versão própria** —
  mudanças dele pegam carona nas tags SemVer do baseline. O CHANGELOG do `v1.2.0`
  (release de *segurança*) foi dominado por entradas do oli-dev.
- **Acoplamento de gate backwards.** A regra de ouro nº 1 do `oli-devops`
  ("nunca tagear sem self-test verde") + o job `plugin-tests` no `self-test.yml`
  fazem uma **falha de teste do plugin travar um release de segurança** (ex.: um
  patch de CVE). O inverso também: um ajuste de doc do plugin arrasta o self-test
  inteiro do baseline.

**Objetivo:** extrair o plugin para um repo/marketplace próprio, com versionamento
independente, preservando o histórico, sem janela em que o plugin fique
indisponível.

## Decisões (fechadas no brainstorming)

| # | Decisão | Escolha |
|---|---|---|
| 1 | Formato do repo-destino | Marketplace guarda-chuva **`oli-plugins`**, mantendo o layout `plugins/oli-dev/` (não hoist para a raiz). Nasce como home de plugins futuros do ecossistema. |
| 2 | Histórico git | **Preservar** via `git filter-repo` (blame/co-autoria/racional). O plugin mantém o path `plugins/oli-dev/` (sem rename); só os design docs são co-localizados sob o plugin. |
| 3 | Cutover | **Big bang**: repo novo primeiro (histórico + CI verde + tag), depois um PR no `oli-devops` remove o plugin. Sem manutenção dupla. |
| 4 | Versionamento | **Tag por plugin**: `oli-dev-v1.0.0` + GitHub release + CHANGELOG. O `plugin.json` fica **sem campo `version`** (invariante documentada: pinar versão obriga bump a cada mudança ou o `/plugin update` serve cache velho; sem versão ele segue o SHA — sempre fresco). Primeira release **v1.0.0** (plugin maduro; a tag/release carrega a versão, não o manifesto). |

## Repo novo `oli-plugins`

### Layout
```
oli-plugins/
  .claude-plugin/
    marketplace.json            # name: "oli-plugins"; lista oli-dev, source ./plugins/oli-dev
  plugins/
    oli-dev/
      .claude-plugin/plugin.json  # SEM campo "version" (invariante: stale-cache)
      commands/  skills/  hooks/  tests/  evals/  README.md
      docs/superpowers/{specs,plans}/   # os 11 design docs do oli-dev, co-localizados
  .github/workflows/ci.yml        # shellcheck + suíte run_all.sh (o que sai do self-test do oli-devops)
  CHANGELOG.md  LICENSE  README.md  policies/SEMVER.md (política do marketplace)
```

**Docs co-localizados:** os 11 `*oli-dev*` de `docs/superpowers/` migram para
`plugins/oli-dev/docs/superpowers/` — no modelo multi-plugin, doc de design
pertence ao plugin que documenta. (Decisão de layout; alternativa era manter em
`docs/` na raiz — rejeitada por não escalar quando vier o 2º plugin.)

### Migração de histórico (`git filter-repo`)
Sobre um **clone fresco** do `oli-devops` (filter-repo reescreve história —
nunca rodar no checkout de trabalho):

1. Extrair só os caminhos do plugin e seus docs, preservando o prefixo
   `plugins/oli-dev/` e renomeando os docs para dentro do plugin:
   - `--path plugins/oli-dev/`
   - `--path-glob 'docs/superpowers/*/*oli-dev*'` com
     `--path-rename docs/superpowers/:plugins/oli-dev/docs/superpowers/`
   - O glob `*oli-dev*` **exclui este meta-spec** (`oli-plugins-split`), que
     permanece no `oli-devops` como registro da extração.
2. Adicionar `.claude-plugin/marketplace.json` (name `oli-plugins`) e o `ci.yml`.
3. Commits de scaffolding (marketplace, CI, LICENSE, CHANGELOG, SEMVER) por cima.

O detalhamento exato dos comandos fica no plano de implementação.

### Fixups (o que quebra ao sair do `oli-devops`)
- **`plugins/oli-dev/tests/test_manifests.sh` linha 22:** assert
  `marketplace.name == "oli-devops"` → `"oli-plugins"`. **É o único fixup do teste.**
- **`test_manifests.sh` linha 5 (`ROOT=.../../../..`):** **não muda** — como
  mantemos `plugins/oli-dev/`, os 3 níveis (`tests`→`oli-dev`→`plugins`→raiz)
  continuam corretos.
- **`test_manifests.sh` linha 28 (`assert "version" not in pj`):** **não muda** —
  o `plugin.json` continua sem `version` (decisão 4). Não adicionar o campo.
- **`plugins/oli-dev/README.md`:** `marketplace add devoliveiraeolivi/oli-devops`
  → `.../oli-plugins`.

### Versionamento (nova `SEMVER.md` do `oli-plugins`)
SemVer por plugin, tag prefixada (`oli-dev-vX.Y.Z`):
- **MAJOR:** quebra na interface `/oli-dev` (flags, sintaxe) ou remoção de fase/gate.
- **MINOR:** nova fase/gate/tier, ou novo plugin no marketplace.
- **PATCH:** fix/docs sem mudança de comportamento.
Release do GitHub intitulado `oli-dev v1.0.0`. CHANGELOG com seção por versão.

### CI do repo novo (`ci.yml`)
Espelha o que sai do `self-test.yml` do oli-devops:
- `shellcheck plugins/oli-dev/{hooks,tests}/*.sh`
- `sh plugins/oli-dev/tests/run_all.sh` (matriz sh+dash, GNU sed — ubuntu runner)
Gate de release: CI verde antes de qualquer tag `oli-dev-vX.Y.Z`.

## Cleanup do `oli-devops` (PR de remoção)

Um único PR, **depois** do `oli-plugins` estar no ar com CI verde e tag `oli-dev-v1.0.0`:

**Remove:**
- `plugins/oli-dev/` (árvore inteira)
- `.claude-plugin/marketplace.json` (e o dir `.claude-plugin/` se ficar vazio)
- os 11 `docs/superpowers/{specs,plans}/*oli-dev*` (preservados no repo novo)
- `self-test.yml`: a linha do `shellcheck ...plugins/oli-dev...` (l.28) e o job
  `plugin-tests` (l.30-39)

**Adiciona:**
- Ponteiro no `README.md` do oli-devops: seção curta "O plugin oli-dev mudou-se
  para `devoliveiraeolivi/oli-plugins`" com o novo comando de instalação.
- Entrada no `CHANGELOG.md` (`### Changed`/`Removed`) documentando a saída.

**Preserva intacto:** todos os jobs de segurança do `self-test.yml`
(shellcheck de `scripts/`, yamllint, schema, fixtures trivy/gitleaks), scripts,
policies, templates. Este meta-spec (`oli-plugins-split-design.md`) fica no
oli-devops como registro.

## Sequência de cutover (big bang, sem janela)

1. Criar `oli-plugins` no GitHub (vazio).
2. Clone fresco do oli-devops → `filter-repo` → push para `oli-plugins`.
3. Scaffolding (marketplace, ci.yml, LICENSE, CHANGELOG, SEMVER) + fixups.
4. CI verde no `oli-plugins`.
5. Tag `oli-dev-v1.0.0` + GitHub release.
6. Smoke test: `/plugin marketplace add devoliveiraeolivi/oli-plugins` +
   `/plugin install oli-dev` + `/oli-dev` roda.
7. **Só então** abrir o PR de remoção no `oli-devops`; mergear com self-test verde.

## Fora de escopo (YAGNI)

- Janela de depreciação / shell de marketplace no oli-devops (base de instalação
  = o próprio ecossistema, um dono → custo de migração baixo).
- Mover specs de **segurança** (`2026-04-08-oli-devops-security-baseline-design.md`
  vive no oli-gateway; os deste repo que não são oli-dev — nenhum hoje — ficariam).
- Reorganização de docs por-plugin além do oli-dev (só quando o 2º plugin existir).

## Definition of Done

- [ ] `oli-plugins` no ar, histórico do plugin preservado (blame aponta commits originais).
- [ ] CI verde no `oli-plugins`; tag `oli-dev-v1.0.0` + release publicados.
- [ ] `/plugin marketplace add .../oli-plugins` + `install oli-dev` + `/oli-dev` funcionam.
- [ ] PR de remoção no `oli-devops` mergeado; self-test de segurança verde sem os jobs do plugin.
- [ ] `README` de ambos os repos consistentes com o novo endereço de instalação.
