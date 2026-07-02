# Fase 0 — SETUP gate

1. **Modelo.** Confirme que o loop principal está em Opus 4.8. Skill não troca modelo: se não
   estiver, **bloqueie** e peça `/model` (ou `/fast` no Opus). Não prossiga sem confirmação.
2. **Dependências.** Verifique que as skills do superpowers necessárias existem
   (brainstorming, writing-plans, subagent-driven-development, test-driven-development,
   requesting-code-review, using-git-worktrees, finishing-a-development-branch,
   verification-before-completion). Se faltar, avise e pare.
   `using-git-worktrees` só é exigida no caminho de **fallback** do passo 3 (EnterWorktree nativo
   indisponível); a ausência dela não bloqueia quando o caminho nativo existe.
3. **Worktree (da main).** `git fetch` + garanta `main` atualizada. Crie o worktree **a partir da
   main** — nunca de outra feature branch, nunca pasta irmã do repo. Prefira o **EnterWorktree
   nativo** (cria em `.claude/worktrees/`, já no `.gitignore`); sem ele, fallback
   `superpowers:using-git-worktrees` (mecânica é da skill; garanta `.worktrees/` no `.gitignore`
   nesse caminho).
4. **Resume/checkpoint.** Detecte artefatos: spec+plano → retome Fase 4; só spec → Fase 2/3;
   nada → Fase 1. Anuncie de onde retoma e confirme antes de pular fases.
5. **Guard de branch ao retomar.** Antes de retomar trabalho numa branch existente, cheque:
   (a) estamos num **worktree linkado** (`git rev-parse --git-dir` ≠ `--git-common-dir`); e
   (b) a PR da branch **não** está MERGED (`gh pr view <branch> --json state`). Se a branch já
   está MERGED → **barre**: commits aqui viram órfãos (aconteceu na PR #4 → recovery na #5);
   crie uma branch nova da `main`. Se estamos no checkout principal (sem worktree) → volte para
   a `main` e crie o worktree. A enforcement determinística disto vive no hook
   `hooks/branch-state-guard.sh`; este passo é a orientação correspondente.
6. **Tier de modelo.** Parseie o tier (`references/model-tiers.md`): default `full`; `light` só
   se for a 1ª palavra seguida de ideia. **Ecoe a interpretação** ("tier=X, ideia='…'") antes de
   agir. Se `light` tocar contrato/enforcement/superfície sensível → recomende `full` e peça
   **ack** explícito. No **resume** (spec+plano → Fase 4), leia o tier do cabeçalho do plano;
   ausente → `full` (fallback seguro).
7. **Ponytail por tier (opcional, fail-open).** "Disponível" = o comando `/ponytail` aparece entre
   os comandos/skills da sessão (mesmo mecanismo do passo 2); se a invocação responder comando
   desconhecido/erro, trate como ausente. Ramos:
   - **tier=`light` + disponível** → invoque `/ponytail lite`. **Evidência**: cole o output da
     invocação ou, se não houver texto capturável, o de `/ponytail` sem argumento (reporta o
     nível). Se nenhum produzir texto, anuncie "sem output capturável" e siga (registre na PR).
   - **tier=`full`** (ponytail presente ou ausente) → **não toque no ponytail** (não ligar ≠
     desligar: se o usuário o ligou globalmente por escolha própria, o ciclo não sobrescreve).
   - **tier=`light` + ausente** → anuncie ("ponytail ausente — seguindo sem pressão ambiente")
     e siga. Ausência NUNCA bloqueia o ciclo.
   Nota (1º ciclo do trial): o alcance da injeção ambiente nos subagentes despachados (escritores
   TDD da Fase 4) não está verificado — observe e registre o resultado como item em
   `## Pontas soltas / follow-ups` da PR (Fase 7), que o close-out transcreve para `issues.md`.
