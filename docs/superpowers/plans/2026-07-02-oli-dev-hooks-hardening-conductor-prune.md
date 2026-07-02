# oli-dev hooks hardening + poda do condutor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fechar a classe de bugs de portabilidade-sh dos hooks (matriz de shells + shellcheck + CI ubuntu) e realinhar o condutor com a prática (EnterWorktree nativo, delegação ao superpowers).

**Tier:** full (escritores TDD e staff-reviewer em Opus)

**Architecture:** Tudo aditivo nos testes/CI (comportamento dos hooks inalterado, exceto 1 mensagem informativa de stderr). A matriz parametriza o interpretador com que o **hook** é invocado dentro dos helpers de teste (`OLI_DEV_TEST_SHELL`); o payload de cobertura é o novo job `plugin-tests` no ubuntu (dash + GNU sed). A poda é docs-only + 1 linha de mensagem.

**Tech Stack:** POSIX sh, shellcheck, GitHub Actions (self-test.yml), markdown (skill references).

**Spec:** `docs/superpowers/specs/2026-07-02-oli-dev-hooks-hardening-conductor-prune-design.md`

## Global Constraints

- Regra de ouro #3: NUNCA renomear hook IDs. #5: CHANGELOG no MESMO commit da mudança (seção `[Unreleased]`).
- Comportamento de bloqueio dos hooks inalterado: os 38 asserts de hook existentes passam sem editar expectativa.
- Convenções: comentários/docs em português; largura ~100 col nos .md do plugin; testes POSIX sh (sem bashismo).
- `SC2069` nos helpers `gate_err` é ORDEM INTENCIONAL (captura stderr, descarta stdout) — corrigir só com `# shellcheck disable=SC2069`; NUNCA reordenar para `>/dev/null 2>&1` (quebra os asserts de stderr).
- Worktree deste ciclo: `/Users/cesarbatista/Documents/GitHub/oli-devops/.claude/worktrees/feat-oli-dev-hooks-hardening` (todos os paths abaixo são relativos a ele).

---

### Task 1: Matriz de shells — `OLI_DEV_TEST_SHELL` parametriza a invocação interna do hook

**Files:**
- Modify: `plugins/oli-dev/tests/test_pre_push_gate.sh:11,14` (helpers `gate_rc`/`gate_err`)
- Modify: `plugins/oli-dev/tests/test_branch_state_guard.sh:8,10` (helpers `gate_rc`/`gate_err`)
- Modify: `plugins/oli-dev/tests/run_all.sh` (loop de matriz {sh, dash} p/ os 2 testes de hook)
- Modify: `CHANGELOG.md` (seção `[Unreleased]` → `### Added`)

**Interfaces:**
- Produces: env-var `OLI_DEV_TEST_SHELL` (interpretador do HOOK nos helpers; default `sh`); `run_all.sh` com matriz `SHELLS="sh dash"` e skip anunciado. Task 2 e 3 dependem desses nomes.

- [ ] **Step 1: RED — provar que hoje a var é ignorada.** Rode:
```bash
cd plugins/oli-dev/tests && OLI_DEV_TEST_SHELL=/usr/bin/false sh test_pre_push_gate.sh; echo "rc=$?"
```
Expected hoje: `pre_push_gate: 15 passed, 0 failed`, rc=0 (a var não faz nada — é o buraco).

- [ ] **Step 2: Parametrizar os helpers.** Em `test_pre_push_gate.sh`, troque APENAS a invocação do hook nas duas linhas de helper (mantenha o resto da linha idêntico):
```sh
# linha 11 — de:
gate_rc() { json="$1"; shift; rc=0; printf '%s' "$json" | env "$@" sh "$GATE" >/dev/null 2>&1 || rc=$?; echo "$rc"; }
# para:
gate_rc() { json="$1"; shift; rc=0; printf '%s' "$json" | env "$@" "${OLI_DEV_TEST_SHELL:-sh}" "$GATE" >/dev/null 2>&1 || rc=$?; echo "$rc"; }
# linha 14 — de:
gate_err() { json="$1"; shift; printf '%s' "$json" | env "$@" sh "$GATE" 2>&1 >/dev/null; }
# para:
gate_err() { json="$1"; shift; printf '%s' "$json" | env "$@" "${OLI_DEV_TEST_SHELL:-sh}" "$GATE" 2>&1 >/dev/null; }
```
Em `test_branch_state_guard.sh` faça a MESMA troca nas linhas 8 e 10 (helpers idênticos, com `"$GUARD"` no lugar de `"$GATE"`).

- [ ] **Step 3: GREEN do RED do Step 1 + sanity nas 3 variantes.** Rode:
```bash
cd plugins/oli-dev/tests
OLI_DEV_TEST_SHELL=/usr/bin/false sh test_pre_push_gate.sh; echo "rc=$?"   # agora DEVE falhar (rc=1, vários FAIL)
sh test_pre_push_gate.sh && sh test_branch_state_guard.sh                   # default sh → 15/0 e 23/0
OLI_DEV_TEST_SHELL=dash sh test_pre_push_gate.sh && OLI_DEV_TEST_SHELL=dash sh test_branch_state_guard.sh  # dash → 15/0 e 23/0
```
Expected: falha com `/usr/bin/false`; GREEN sob `sh` e `dash`.

- [ ] **Step 4: Matriz no `run_all.sh`.** Substitua o loop atual (linhas 4-8) por:
```sh
rc=0

# Testes de hook rodam 1x por shell da matriz: OLI_DEV_TEST_SHELL parametriza o interpretador
# com que o HOOK é invocado dentro dos helpers (não o arquivo de teste — isso seria teatro).
# Payload principal de portabilidade é o job plugin-tests do CI (ubuntu: dash + GNU sed);
# a matriz local dá feedback rápido. Shell ausente = skip anunciado, nunca silencioso.
MATRIX_TESTS=" test_pre_push_gate.sh test_branch_state_guard.sh "
SHELLS="sh dash"

for t in "$HERE"/test_*.sh; do
  name="$(basename "$t")"
  case "$MATRIX_TESTS" in
    *" $name "*)
      for s in $SHELLS; do
        if command -v "$s" >/dev/null 2>&1; then
          echo "=== $name [hook shell: $s] ==="
          OLI_DEV_TEST_SHELL="$s" sh "$t" || rc=1
        else
          echo "=== $name [hook shell: $s] === SKIP: shell '$s' ausente"
        fi
      done
      ;;
    *)
      echo "=== $name ==="
      sh "$t" || rc=1
      ;;
  esac
done
```
(Atenção à lição do fix `591e63d`: nada de `case` com padrões dentro de `$(...)`; aqui o `case` está no corpo normal do script.)

- [ ] **Step 5: Suíte plena.** Rode: `sh plugins/oli-dev/tests/run_all.sh`
Expected: os 2 testes de hook aparecem 2× cada (`[hook shell: sh]` e `[hook shell: dash]`), demais 1×, e `ALL GREEN`.

- [ ] **Step 6: CHANGELOG (mesmo commit).** Em `CHANGELOG.md`, seção `[Unreleased]` → `### Added`, adicione:
```markdown
- **`oli-dev` testes: matriz de shells nos testes de hook** (`OLI_DEV_TEST_SHELL`): os helpers
  `gate_rc`/`gate_err` passam a invocar o hook com o shell da matriz ({`sh`, `dash`}, via
  `run_all.sh`, skip anunciado se ausente) — o hook é exercitado sob cada shell, não o arquivo
  de teste. Feedback local rápido p/ a classe de bugs de portabilidade-sh (3 fugas históricas).
```

- [ ] **Step 7: Commit.**
```bash
git add plugins/oli-dev/tests/test_pre_push_gate.sh plugins/oli-dev/tests/test_branch_state_guard.sh plugins/oli-dev/tests/run_all.sh CHANGELOG.md
git commit -m "feat(oli-dev): matriz de shells nos testes de hook (OLI_DEV_TEST_SHELL, sh+dash)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: `test_shellcheck.sh` + zerar os achados existentes nos testes

**Files:**
- Create: `plugins/oli-dev/tests/test_shellcheck.sh`
- Modify: `plugins/oli-dev/tests/test_pre_push_gate.sh` e `test_branch_state_guard.sh` (diretivas `# shellcheck disable` nos achados SC2015/SC2069)
- Modify: `CHANGELOG.md` (`[Unreleased]` → `### Added`, mesma bullet-família da Task 1)

**Interfaces:**
- Consumes: helpers já parametrizados pela Task 1 (as linhas com SC2069 agora contêm `"${OLI_DEV_TEST_SHELL:-sh}"`).
- Produces: `tests/test_shellcheck.sh` (roda no glob do `run_all.sh` automaticamente, fora da matriz). Task 3 usa o mesmo escopo de lint no CI.

- [ ] **Step 1: Criar o teste (ele nasce RED).** Crie `plugins/oli-dev/tests/test_shellcheck.sh`:
```sh
#!/usr/bin/env sh
# Trava de regressão de estilo/armadilha nos scripts do plugin. NÃO é caça-bug de
# portabilidade (nenhuma das 3 fugas históricas era detectável por shellcheck) — o
# eixo de portabilidade é a matriz de shells + o job plugin-tests do CI.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
if ! command -v shellcheck >/dev/null 2>&1; then
  echo "SKIP: shellcheck ausente — lint não checado localmente (o CI roda sempre)."
  echo "PASS test_shellcheck (skipped)"
  exit 0
fi
shellcheck "$HERE"/../hooks/*.sh "$HERE"/*.sh
echo "PASS test_shellcheck"
```
`chmod +x plugins/oli-dev/tests/test_shellcheck.sh`.

- [ ] **Step 2: RED.** Rode: `sh plugins/oli-dev/tests/test_shellcheck.sh`
Expected: FAIL com ~6 achados, todos em `tests/*.sh` (4× SC2015 info no idioma `pwd -W … || pwd`; 2× SC2069 nos `gate_err`). Hooks limpos (0 achados). Anote a lista exata do output.

- [ ] **Step 3: GREEN — diretivas, nunca reordenação.** Para cada achado do Step 2, adicione a diretiva NA LINHA ANTERIOR:
```sh
# SC2015: A && B || C aqui é intencional (pwd -W só existe no Git-Bash/Windows; fallback pwd).
# shellcheck disable=SC2015
HERE="$(cd "$(dirname "$0")" && pwd -W 2>/dev/null || pwd)"
```
```sh
# SC2069: ordem intencional — captura stderr p/ asserts de mensagem, descarta stdout.
# shellcheck disable=SC2069
gate_err() { json="$1"; shift; printf '%s' "$json" | env "$@" "${OLI_DEV_TEST_SHELL:-sh}" "$GATE" 2>&1 >/dev/null; }
```
(No `test_branch_state_guard.sh` o mesmo padrão com `"$GUARD"`.) PROIBIDO "corrigir" SC2069 trocando para `>/dev/null 2>&1` — quebra os testes de stderr (`checkc`).

- [ ] **Step 4: Verificar GREEN + suíte plena.** Rode:
```bash
sh plugins/oli-dev/tests/test_shellcheck.sh   # PASS test_shellcheck
sh plugins/oli-dev/tests/run_all.sh           # ALL GREEN (novo teste entra no glob, fora da matriz)
```

- [ ] **Step 5: CHANGELOG (mesmo commit).** Na bullet adicionada na Task 1, acrescente ao final:
```markdown
  Novo `tests/test_shellcheck.sh` (skip anunciado sem shellcheck local) linta `hooks/*.sh` +
  `tests/*.sh`; achados pré-existentes nos testes zerados via diretivas justificadas (SC2015/SC2069).
```

- [ ] **Step 6: Commit.**
```bash
git add plugins/oli-dev/tests/test_shellcheck.sh plugins/oli-dev/tests/test_pre_push_gate.sh plugins/oli-dev/tests/test_branch_state_guard.sh CHANGELOG.md
git commit -m "feat(oli-dev): test_shellcheck no plugin (hooks + testes; skip anunciado sem shellcheck)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: CI — shellcheck cobre o plugin + job `plugin-tests` (ubuntu)

**Files:**
- Modify: `.github/workflows/self-test.yml` (job `shellcheck` linha ~26; novo job `plugin-tests` após `shellcheck`)
- Modify: `CHANGELOG.md` (`[Unreleased]` → `### Added`)

**Interfaces:**
- Consumes: `run_all.sh` com matriz + `test_shellcheck.sh` (Tasks 1-2).
- Produces: job `plugin-tests` — critério de aceite 3 da spec (verde na PR).

- [ ] **Step 1: Estender o job shellcheck.** Em `.github/workflows/self-test.yml`, no step `Run shellcheck` (linha ~23-26), troque:
```yaml
        run: |
          sudo apt-get update -qq
          sudo apt-get install -qq shellcheck
          shellcheck -x --source-path=scripts scripts/*.sh
```
por:
```yaml
        run: |
          sudo apt-get update -qq
          sudo apt-get install -qq shellcheck
          shellcheck -x --source-path=scripts scripts/*.sh
          # Hooks/testes do plugin não fazem source → sem --source-path extra.
          shellcheck plugins/oli-dev/hooks/*.sh plugins/oli-dev/tests/*.sh
```

- [ ] **Step 2: Novo job `plugin-tests`.** Logo após o job `shellcheck` (antes de `yamllint:`), insira:
```yaml
  plugin-tests:
    name: oli-dev plugin tests (dash + GNU sed)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - name: Run plugin suite
        # Ubuntu: /bin/sh = dash e sed = GNU — o eixo de portabilidade que o macOS local
        # não cobre (classe das 3 fugas históricas). dash vem no runner; se um dia faltar,
        # o run_all anuncia o skip (aí sim instalar via apt).
        run: sh plugins/oli-dev/tests/run_all.sh
```

- [ ] **Step 3: Validar o YAML localmente.** Rode (na ordem de preferência; use o primeiro disponível):
```bash
uvx yamllint -d '{extends: default, rules: {line-length: {max: 140}, document-start: disable, truthy: {check-keys: false}}}' .github/workflows/self-test.yml \
  || python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/self-test.yml')); print('YAML OK')"
```
Expected: sem erros (mesma config do job `yamllint` do CI; nenhuma linha > 140 col).

- [ ] **Step 4: CHANGELOG (mesmo commit).** `[Unreleased]` → `### Added`:
```markdown
- **`self-test.yml`: cobertura de CI para o plugin oli-dev** — job `shellcheck` passa a lintar
  `plugins/oli-dev/{hooks,tests}/*.sh`, e novo job `plugin-tests` roda a suíte no ubuntu
  (`/bin/sh` = dash + GNU sed): é o eixo de ambiente que o macOS local não cobre e por onde as
  3 fugas históricas de portabilidade escaparam. A suíte do plugin deixa de ser local-only.
```

- [ ] **Step 5: Commit.**
```bash
git add .github/workflows/self-test.yml CHANGELOG.md
git commit -m "ci(self-test): shellcheck cobre plugin oli-dev + job plugin-tests (ubuntu: dash + GNU sed)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Poda/realinhamento do condutor (docs + mensagem do guard)

**Files:**
- Modify: `plugins/oli-dev/skills/dev-cycle/references/setup-gate.md` (§2 e §3)
- Modify: `plugins/oli-dev/skills/dev-cycle/references/finalize.md` (§4)
- Modify: `plugins/oli-dev/skills/dev-cycle/SKILL.md` (bullet da Fase 0)
- Modify: `plugins/oli-dev/hooks/branch-state-guard.sh:73` (mensagem informativa, não-bloqueio)
- Modify: `CHANGELOG.md` (`[Unreleased]` → `### Changed`)

**Interfaces:**
- Consumes: matriz de testes (Task 1) — os testes do guard validam que a mudança de mensagem não quebra nada (`test_branch_state_guard.sh:48` asserta a palavra "worktree", não o path — verificado no staff-review).
- Produces: nada consumido por outras tasks (última).

- [ ] **Step 1: RED estrutural.** Rode ANTES de editar (baseline de segurança):
```bash
sh plugins/oli-dev/tests/test_references.sh && sh plugins/oli-dev/tests/test_skill_structure.sh && sh plugins/oli-dev/tests/test_branch_state_guard.sh
```
Expected: `PASS test_references`, `PASS test_skill_structure`, `branch_state_guard: 23 passed, 0 failed`. (Se algo já falha, PARE e reporte.)

- [ ] **Step 2: `setup-gate.md`.** No §2 (Dependências), após a lista de skills, acrescente a frase:
```markdown
   `using-git-worktrees` só é exigida no caminho de **fallback** do passo 3 (EnterWorktree nativo
   indisponível); a ausência dela não bloqueia quando o caminho nativo existe.
```
Substitua o §3 inteiro por:
```markdown
3. **Worktree (da main).** `git fetch` + garanta `main` atualizada. Crie o worktree **a partir da
   main** — nunca de outra feature branch. Prefira o **EnterWorktree nativo** (cria em
   `.claude/worktrees/`, já no `.gitignore`); sem ele, fallback `superpowers:using-git-worktrees`
   (mecânica é da skill; garanta `.worktrees/` no `.gitignore` nesse caminho).
```

- [ ] **Step 3: `finalize.md` §4.** Substitua o passo 4 inteiro por:
```markdown
4. **Remove worktree.** Delegue a mecânica (inclusive caveats de plataforma, ex. junctions no
   Windows) a `superpowers:finishing-a-development-branch`. Vale para ambos os locais
   (`.claude/worktrees/` nativo ou `.worktrees/` fallback).
```

- [ ] **Step 4: `SKILL.md` Fase 0.** No bullet da Fase 0, troque o trecho `+ cria worktree da main.` por `+ cria worktree da main (EnterWorktree nativo preferido; fallback \`using-git-worktrees\`).`

- [ ] **Step 5: Mensagem do guard.** Em `plugins/oli-dev/hooks/branch-state-guard.sh:73`, troque:
```sh
  echo "oli-dev guard: trabalhando no checkout principal numa feature branch ('$branch') — considere um worktree (.worktrees/<feat>)." >&2
```
por:
```sh
  echo "oli-dev guard: trabalhando no checkout principal numa feature branch ('$branch') — considere um worktree." >&2
```

- [ ] **Step 6: GREEN + suíte plena.** Rode: `sh plugins/oli-dev/tests/run_all.sh`
Expected: `ALL GREEN` (em particular `test_references`, `test_skill_structure` e o guard 23/0 sob sh e dash — o assert da linha 48 casa com a palavra "worktree" que permanece na mensagem).

- [ ] **Step 7: CHANGELOG (mesmo commit).** `[Unreleased]` → `### Changed`:
```markdown
- **`oli-dev` condutor realinhado à prática e podado de duplicação com o superpowers**:
  `setup-gate.md` prefere o **EnterWorktree nativo** (`.claude/worktrees/`) com
  `using-git-worktrees` como fallback (dep exigida só nesse caminho; gitignore do path usado);
  `finalize.md` delega a mecânica de remoção de worktree a `finishing-a-development-branch`
  (caveat Windows/junction sai — vive na skill do superpowers); mensagem informativa do
  `branch-state-guard.sh` fica agnóstica de local. Gates OLI (da main, MERGED antes de deletar,
  close-out) intactos.
```

- [ ] **Step 8: Commit.**
```bash
git add plugins/oli-dev/skills/dev-cycle/references/setup-gate.md plugins/oli-dev/skills/dev-cycle/references/finalize.md plugins/oli-dev/skills/dev-cycle/SKILL.md plugins/oli-dev/hooks/branch-state-guard.sh CHANGELOG.md
git commit -m "docs(oli-dev): condutor prefere EnterWorktree nativo + delega mecânica ao superpowers (poda)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```
