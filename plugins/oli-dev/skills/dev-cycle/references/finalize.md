# Fase 8 — FINALIZE (close-out + limpeza pós-merge)

Rodada por `/oli-dev finalize`, DEPOIS que a PR foi mergeada. Ordem:

1. **Verifica merge.** `gh pr view <n> --json state` → exija `state == "MERGED"`. NUNCA delete
   branch sem isso (lição #257). Se não estiver MERGED, **aborte** e informe.
2. **PRs stacked.** Se havia PRs empilhadas sobre esta, re-aponte a base delas para `main` antes
   de qualquer limpeza.
3. **Volta para main.** `cd` no dir principal, `git checkout main && git pull`.
4. **Remove worktree.** Delegue a mecânica (inclusive caveats de plataforma, ex. junctions no
   Windows) a `superpowers:finishing-a-development-branch`. Vale para ambos os locais
   (`.claude/worktrees/` nativo ou `.worktrees/` fallback).
5. **Deleta branches (só após passo 1).** `git branch -d` (nunca `-D`) + `commit-commands:clean_gone`.
6. **Close-out.** Siga `assets/close-out-checklist.md`.
