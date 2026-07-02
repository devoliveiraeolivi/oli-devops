# Registro de trabalho e follow-ups

Formato: uma entrada por PR/ticket (o que mudou em 1-2 linhas) + follow-ups rastreáveis.
Fonte: seções `## Summary` e `## Pontas soltas / follow-ups` das PRs mergeadas (close-out da Fase 8).

## Entregas

- **PR #14** (2026-07-02) — `oli-dev` hooks hardening + poda do condutor: matriz de shells
  ({sh, dash}) exercitando o *hook* via `OLI_DEV_TEST_SHELL` (introspecção + meta-assert
  anti-teatro), `test_shellcheck.sh`, job `plugin-tests` no self-test (ubuntu: dash + GNU sed —
  a suíte do plugin deixou de ser local-only); condutor prefere EnterWorktree nativo e delega ao
  superpowers só onde a cobertura é real (caveat Windows/junction mantido no `finalize.md`).

- **PR #17** (2026-07-02) — `oli-dev` tier `light` ativa `/ponytail lite` na Fase 0 (opcional,
  fail-open): com o plugin ponytail presente, o ciclo light liga a pressão anti-over-engineering
  ambiente automaticamente; `full` não toca; ausência anuncia e segue. Detecção autocontida,
  evidência com rótulo `⚠️ não verificado`, README/comando documentam. **Trial validado pelo
  usuário em 2026-07-02** ("testei e vale a pena") → integração mantida; nota temporária do
  passo 7 removida no close-out.

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
      ~520k; fixer 77k). **Dado da PR #17 (tier light, diff docs-only pequeno): ~350k tokens**
      (staff-review Sonnet 49k; task-review 42k; code-review medium ~240k; fixer 75k) — indicativo,
      diffs de tamanhos diferentes. Falta 1-2 ciclos light em fatia de código p/ decidir o default.
- [ ] **Guard bloqueia `git push --delete` no finalize (falso-positivo)** — observado no finalize
      da PR #17: o `branch-state-guard.sh` bloqueia qualquer `git push` com cwd numa branch MERGED,
      inclusive o `git push origin --delete <branch>` que é exatamente a operação sancionada da
      Fase 8. Contorno usado: deletar a partir do checkout principal (main). Fix candidato:
      permitir `push --delete`/`push -d` da própria branch merged no guard (adição de caso, com
      teste). Baixa urgência — o contorno é trivial e o finalize.md já orienta voltar pra main.
- [ ] **Premissas do ponytail ainda não verificadas de forma independente** — o trial do usuário
      validou o valor prático (2026-07-02), mas as duas premissas técnicas da nota removida seguem
      sem verificação instrumentada: (a) a injeção ambiente alcançar os subagentes da Fase 4;
      (b) o modo per-session não persistir entre sessões. Verificar oportunisticamente no próximo
      ciclo light com ponytail ativo (perguntar a um writer se o ladder está no contexto dele;
      checar `/ponytail` numa sessão nova) — se (a) for falso, reavaliar a integração.
