---
name: dev-cycle
description: Use ao construir uma feature/mudança nova no ecossistema OLI — conduz o ciclo completo (worktree da main, brainstorm, review staff cético, plano, escrita TDD por subagente com modelo por tier, review code/simplify/verify, pre-push gate, PR, finalize pós-merge). Invocada por `/oli-dev [light] <ideia>` e `/oli-dev finalize`.
---

# dev-cycle — maestro do ciclo de desenvolvimento OLI

## When to Use

- `/oli-dev [light] <ideia>` → ciclo completo (Fases 0–7), termina em PR aberta. Tier `full` (default) ou `light` (escritores TDD + staff-reviewer em Sonnet) — ver `references/model-tiers.md`.
- `/oli-dev finalize` → só a Fase 8 (close-out + limpeza), depois que a PR foi mergeada.
- Ative também quando o usuário descreve uma feature nova e pede para "construir/implementar".

NÃO use para: hotfix trivial de 1 linha já aprovado, perguntas, ou tarefas sem código.

## Prerequisites

- Plugin **superpowers** instalado (esta skill o invoca). Se faltar, avise e pare.
- Loop principal em **Opus 4.8** (verificado na Fase 0).
- Repo alvo é um git repo com `main` e remoto configurado.

## Princípios de processo (gates duros — invioláveis)

1. Uma branch por ciclo, **da `main`**. Sem PRs stacked por padrão.
2. **Worktree sempre, da `main`.** Nunca trabalhar direto numa branch no dir principal.
3. **Nunca deletar branch** — nem continuar empurrando nela — sem `gh pr view <n> --json state`.
   Se a PR está `MERGED`, commits/pushes na branch viram órfãos; o hook `branch-state-guard.sh`
   bloqueia isso de forma determinística (push/commit), e a Fase 0 recusa retomar numa branch mergeada.
4. **Modelo por tier (conductor sempre Opus).** O loop principal (conductor) é **sempre Opus 4.8** —
   Fase 0 checa; cobre plano, adjudicação e os gates inline `/simplify`/`verify`/`/security-review`.
   Os dois papéis despachados seguem o **tier**: escritores TDD (Fase 4) e staff-reviewer (Fase 2)
   → `full` = `model: "opus"` (default), `light` = `model: "sonnet"`. `/code-review` roda seu fleet
   próprio (fora do tier). Effort alto nos reviews. Ver `references/model-tiers.md`.

## Workflow

Mantenha um todo por fase. Modo `<ideia>` = Fases 0–7; modo `finalize` = Fase 8.
Carregue o `references/*.md` da fase **quando ela começa** (progressive disclosure).

- **Fase 0 — SETUP gate** → ver `references/setup-gate.md`. Checa Opus + deps + tier (`full`/`light`) + cria worktree da main (EnterWorktree nativo preferido; fallback `using-git-worktrees`) + ponytail por tier (opcional). Resume/checkpoint: detecta spec/plano existentes e retoma da fase certa (pede confirmação antes de pular).
- **Fase 1 — BRAINSTORM** → invoca `superpowers:brainstorming`. Spec em `docs/superpowers/specs/`. Commit.
- **Fase 2 — REVIEW pré-código** → ver `references/review-gates.md`. 1 `staff-reviewer` cético (modelo por tier: `full`=Opus, `light`=Sonnet). Resolve achados. Commit.
- **Fase 3 — PLANO** → invoca `superpowers:writing-plans`. Commit.
- **Fase 4 — ESCRITA** → invoca `superpowers:subagent-driven-development`; cada task em TDD, subagentes com `model:` por tier (`full`=opus, `light`=sonnet). Pipeline (serial) ou Fan-out (`dispatching-parallel-agents`) conforme dependência. Checkpoint commit por task.
- **Fase 5 — REVIEW pós-código** → ver `references/review-gates.md`. `/code-review` → `/simplify` → `verify`; sub-gate condicional `/security-review` se o diff toca superfície sensível. Idêntica nos dois tiers (conductor adjudica em Opus; `/code-review` tem fleet próprio).
- **Fase 6 — PRE-PUSH gate** → ver `references/pre-push-gate.md`. Prefere `scripts/check.sh --fast` do repo; senão fallback ruff+mypy (ou lint+test+build p/ node). Bloqueia se falhar, com evidência.
- **Fase 7 — PUSH + PR** → `commit-commands:commit-push-pr`. Base = `main`. O push leva o prefixo `OLI_DEV_GATE_OK=1` (gate já rodou na Fase 6 → hook não re-roda). Usa `assets/pr-body-template.md`. Termina aqui.
- **Fase 8 — FINALIZE** (`/oli-dev finalize`) → ver `references/finalize.md`. Verifica `MERGED`, limpa worktree+branch, close-out (`assets/close-out-checklist.md`).

## Verification

Antes de declarar qualquer fase concluída, confirme com **evidência** (output real, nunca alegação):
- Fase 0: worktree existe e está na branch certa (`git worktree list`, `git branch --show-current`);
  se ponytail presente e tier=`light`, o nível foi confirmado com output colado.
- Fase 2/5: o staff-reviewer foi despachado com o `model:` do tier, o conductor adjudicou em Opus, e os achados materiais foram resolvidos.
- Fase 6: os comandos do gate passaram (cole o output).
- Fase 7: a PR foi criada (URL).
- Fase 8: `gh pr view --json state` == `MERGED` antes de qualquer delete; worktree removido; close-out feito.
