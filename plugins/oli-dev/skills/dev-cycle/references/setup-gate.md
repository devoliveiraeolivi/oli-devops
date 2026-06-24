# Fase 0 — SETUP gate

1. **Modelo.** Confirme que o loop principal está em Opus 4.8. Skill não troca modelo: se não
   estiver, **bloqueie** e peça `/model` (ou `/fast` no Opus). Não prossiga sem confirmação.
2. **Dependências.** Verifique que as skills do superpowers necessárias existem
   (brainstorming, writing-plans, subagent-driven-development, test-driven-development,
   requesting-code-review, using-git-worktrees, finishing-a-development-branch,
   verification-before-completion). Se faltar, avise e pare.
3. **Worktree (da main).** `git fetch` + garanta `main` atualizada. Crie
   `.worktrees/<feat>` na branch `feat/<feat>` **a partir da main** via
   `superpowers:using-git-worktrees`. Garanta `.worktrees/` no `.gitignore`. Nunca pasta irmã,
   nunca de outra feature branch.
4. **Resume/checkpoint.** Detecte artefatos: spec+plano → retome Fase 4; só spec → Fase 2/3;
   nada → Fase 1. Anuncie de onde retoma e confirme antes de pular fases.
