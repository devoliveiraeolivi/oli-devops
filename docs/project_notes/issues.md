# Registro de trabalho e follow-ups

Formato: uma entrada por PR/ticket (o que mudou em 1-2 linhas) + follow-ups rastreáveis.
Fonte: seções `## Summary` e `## Pontas soltas / follow-ups` das PRs mergeadas (close-out da Fase 8).

## Entregas

- **PR #14** (2026-07-02) — `oli-dev` hooks hardening + poda do condutor: matriz de shells
  ({sh, dash}) exercitando o *hook* via `OLI_DEV_TEST_SHELL` (introspecção + meta-assert
  anti-teatro), `test_shellcheck.sh`, job `plugin-tests` no self-test (ubuntu: dash + GNU sed —
  a suíte do plugin deixou de ser local-only); condutor prefere EnterWorktree nativo e delega ao
  superpowers só onde a cobertura é real (caveat Windows/junction mantido no `finalize.md`).

## Follow-ups em aberto

- [ ] **Reescrita python3 dos hooks do oli-dev** — deferida na PR #14. Gatilho explícito: um novo
      bug de portabilidade-sh escapar *apesar* da matriz de shells + job `plugin-tests` do CI.
      Enquanto o gatilho não dispara, não fazer (adição > modificação na superfície de enforcement).
- [ ] **Seam `OLI_DEV_GUARD_IN_WORKTREE`** usa `[ -n ]` enquanto `OLI_DEV_GUARD_BRANCH` usa
      `${VAR+x}` (`branch-state-guard.sh`; pré-existente do commit `766f8d7`, provavelmente
      intencional — semânticas distintas, verificado no review da PR #14). Só revisitar se um teste
      precisar de "setado vazio" no seam de worktree.
- [ ] **Regra-dos-três para helpers de teste do plugin** — `gate_rc`/`gate_err` duplicados entre os
      2 testes de hook e bloco SC2015 ×4 arquivos: aceito como está na PR #14; extrair `_lib.sh`
      apenas quando surgir um 3º consumidor do mesmo padrão.
- [ ] **Medir custo por ciclo do /oli-dev** — dado da PR #14 (tier full): ~2h wall-clock, ~900k
      tokens de subagentes (staff-review 48k; escrita TDD + task-reviews ~280k; code-review high
      ~520k; fixer 77k). Coletar o mesmo dado nos próximos 2-3 ciclos (inclusive um `light`) para
      decidir com evidência o default full vs. light.
