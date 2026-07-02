# oli-dev ponytail no tier light — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fase 0 do dev-cycle ativa `/ponytail lite` automaticamente quando tier=`light` e o plugin está presente; `full` não toca; ausência nunca bloqueia.

**Tier:** light (escritores TDD e staff-reviewer em Sonnet)

**Architecture:** Docs-only do condutor (setup-gate.md passo 7 + SKILL.md) + 1 assert de estrutura em test_references.sh. Nenhum hook tocado; `model-tiers.md` fica intacto (princípio "o tier troca apenas o modelo").

**Tech Stack:** Markdown (skill references), POSIX sh (assert).

**Spec:** `docs/superpowers/specs/2026-07-02-oli-dev-ponytail-light-design.md`

## Global Constraints

- Regra de ouro #5: CHANGELOG.md no MESMO commit ([Unreleased] → Added).
- `model-tiers.md` NÃO pode mencionar ponytail (bloqueio 2 do staff-review).
- Invariantes de assert existentes: token `main` em setup-gate.md; seções/links do SKILL.md.
- Docs em português, largura ~100 col.
- Worktree deste ciclo: `/Users/cesarbatista/Documents/GitHub/oli-devops/.claude/worktrees/feat-oli-dev-ponytail-light` (paths relativos a ele).

---

### Task 1: Passo 7 do setup-gate + Verification + assert

**Files:**
- Modify: `plugins/oli-dev/tests/test_references.sh` (assert novo — escreva PRIMEIRO, é o RED)
- Modify: `plugins/oli-dev/skills/dev-cycle/references/setup-gate.md` (novo passo 7)
- Modify: `plugins/oli-dev/skills/dev-cycle/SKILL.md` (bullet Fase 0 + sub-linha na Verification)
- Modify: `CHANGELOG.md` ([Unreleased] → Added)

**Interfaces:**
- Consumes: nada de tasks anteriores (task única).
- Produces: nada (task única).

- [ ] **Step 1: RED — assert novo em test_references.sh.** Após a linha do assert de `main` em setup-gate.md (`grep -qi 'main' "$BASE/references/setup-gate.md" || fail ...`), adicione:
```sh
# Passo do ponytail por tier (opcional, fail-open) documentado na Fase 0
grep -qi 'ponytail' "$BASE/references/setup-gate.md" || fail "setup-gate.md must document the ponytail-by-tier step"
```

- [ ] **Step 2: Rodar e confirmar RED.**
Run: `sh plugins/oli-dev/tests/test_references.sh`
Expected: `FAIL: setup-gate.md must document the ponytail-by-tier step`, exit 1.

- [ ] **Step 3: Novo passo 7 no setup-gate.md.** Apense ao final de `plugins/oli-dev/skills/dev-cycle/references/setup-gate.md` (após o passo 6):
```markdown
7. **Ponytail por tier (opcional, fail-open).** "Disponível" = o comando `/ponytail` aparece entre
   os comandos/skills da sessão (mesmo mecanismo do passo 2); se a invocação responder comando
   desconhecido/erro, trate como ausente. Ramos:
   - **tier=`light` + disponível** → invoque `/ponytail lite`. **Evidência**: cole o output da
     invocação ou, se não houver texto capturável, o de `/ponytail` sem argumento (reporta o
     nível). Se nenhum produzir texto, anuncie "sem output capturável" e siga (registre na PR).
   - **tier=`full`** → **não toque no ponytail** (não ligar ≠ desligar: se o usuário o ligou
     globalmente por escolha própria, o ciclo não sobrescreve).
   - **Ausente (qualquer tier)** → anuncie ("ponytail ausente — seguindo sem pressão ambiente")
     e siga. Ausência NUNCA bloqueia o ciclo.
   Nota (1º ciclo do trial): o alcance da injeção ambiente nos subagentes despachados (escritores
   TDD da Fase 4) não está verificado — observe e registre o resultado como item em
   `## Pontas soltas / follow-ups` da PR (Fase 7), que o close-out transcreve para `issues.md`.
```

- [ ] **Step 4: SKILL.md — bullet da Fase 0 + Verification.**
(a) No bullet da Fase 0 do Workflow, troque `+ cria worktree da main (EnterWorktree nativo preferido; fallback \`using-git-worktrees\`).` por `+ cria worktree da main (EnterWorktree nativo preferido; fallback \`using-git-worktrees\`) + ponytail por tier (opcional).`
(b) Na seção `## Verification`, troque a linha `- Fase 0: worktree existe e está na branch certa (\`git worktree list\`, \`git branch --show-current\`).` por:
```markdown
- Fase 0: worktree existe e está na branch certa (`git worktree list`, `git branch --show-current`);
  se ponytail presente e tier=`light`, o nível foi confirmado com output colado.
```

- [ ] **Step 5: GREEN + suíte plena.**
Run: `sh plugins/oli-dev/tests/test_references.sh` → `PASS test_references`
Run: `sh plugins/oli-dev/tests/run_all.sh` → `ALL GREEN`
Run: `grep -ci ponytail plugins/oli-dev/skills/dev-cycle/references/model-tiers.md` → deve ser `0` (constraint do staff-review).

- [ ] **Step 6: CHANGELOG (mesmo commit).** `[Unreleased]` → `### Added`:
```markdown
- **`oli-dev` Fase 0: ponytail por tier (opcional, fail-open)** — com o plugin ponytail presente
  na sessão, tier `light` ativa `/ponytail lite` automaticamente (evidência de nível colada);
  `full` não toca no ponytail (não sobrescreve escolha global do usuário); ausência anuncia e
  segue. `model-tiers.md` intacto (o tier continua trocando apenas o modelo dos papéis
  despachados). Assert de estrutura novo em `test_references.sh`.
```

- [ ] **Step 7: Commit.**
```bash
git add plugins/oli-dev/tests/test_references.sh plugins/oli-dev/skills/dev-cycle/references/setup-gate.md plugins/oli-dev/skills/dev-cycle/SKILL.md CHANGELOG.md
git commit -m "feat(oli-dev): Fase 0 ativa /ponytail lite no tier light (opcional, fail-open)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```
