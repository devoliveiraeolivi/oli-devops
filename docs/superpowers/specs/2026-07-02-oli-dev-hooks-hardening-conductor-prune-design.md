# oli-dev: hardening dos hooks (shellcheck + matriz de shells + CI) + poda do condutor

**Data:** 2026-07-02 · **Tier:** full · **Origem:** análise de efetividade da skill (sessão de 2026-07-02),
aprovada pelo usuário ("ok, pode fazer").

## Problema

**A. Hooks são o único diferencial real do plugin — e a única fonte de bugs.** 6 fix commits em 8 dias
(`05fb2ef`, `591e63d`, `454db0c`, `984dcb8`, `aeb47c7` + dup de rebase), todos da mesma família:
portabilidade sh (BSD sed vs GNU sed, `case` com `)` dentro de `$()`, `python` vs `python3`). Dois
causaram **falso-bloqueio de push legítimo** (PRs #8 e #12) — o pior modo de falha para um gate.
Causa raiz da fuga: cobertura de ambiente zero-variância —
- o job `shellcheck` do CI (`self-test.yml:17-26`) linta só `scripts/*.sh`; os hooks do plugin ficam fora;
- **nenhum job de CI roda `plugins/oli-dev/tests/run_all.sh`** — a suíte (44 asserts) só roda local;
- local = macOS: `/bin/sh` é bash 3.2 em modo sh + BSD sed. Runtime real inclui ubuntu (dash + GNU sed).
  Os testes invocam os hooks com `sh` hardcoded (`test_pre_push_gate.sh:11`, `test_branch_state_guard.sh:8`).

**B. O condutor re-especifica mecânica que o superpowers já garante, e divergiu da prática.**
- `references/setup-gate.md` §3 manda criar `.worktrees/<feat>` + branch `feat/<feat>` via
  `superpowers:using-git-worktrees`; a prática real desde `35fb284` é o **EnterWorktree nativo**
  (`.claude/worktrees/`, branch `worktree-<nome>` — head da PR #9 e deste ciclo). Doc e realidade divergem.
- `references/finalize.md` §3–5 re-especificam mecânica de remoção de worktree (inclusive caveat
  Windows/junction) que `superpowers:finishing-a-development-branch` já possui.
- `branch-state-guard.sh:73` (mensagem de aviso, não-bloqueio) sugere `.worktrees/<feat>`, local desatualizado.

## Decisão

### A. Hardening dos hooks — **aditivo, sem mudar comportamento dos hooks**

1. **Matriz de shells nos testes.** Os dois testes de hook passam a invocar o script via
   `${OLI_DEV_TEST_SHELL:-sh}`. `run_all.sh` roda `test_pre_push_gate.sh` e `test_branch_state_guard.sh`
   uma vez por shell disponível em {`sh`, `bash`, `dash`}; shell ausente = **skip anunciado** (sem cap
   silencioso). Demais testes rodam 1×.
2. **Shellcheck dos hooks e testes.** Novo `tests/test_shellcheck.sh`: roda `shellcheck` em
   `hooks/*.sh` e `tests/*.sh` quando disponível; ausente = skip anunciado. Achados existentes são
   corrigidos de forma comportamento-preservante (validado pela própria suíte).
3. **CI.** `self-test.yml`: (a) job `shellcheck` passa a incluir `plugins/oli-dev/hooks/*.sh` e
   `plugins/oli-dev/tests/*.sh`; (b) novo job `plugin-tests` (ubuntu: dash como `/bin/sh` + GNU sed)
   roda `sh plugins/oli-dev/tests/run_all.sh` com `dash` instalado. Ubuntu cobre o eixo que o macOS
   local não cobre — exatamente a classe das 3 fugas históricas de portabilidade.

**Alternativa rejeitada (por ora): reescrever os hooks em python3.** Elimina a classe na raiz, mas é
cirurgia na superfície de enforcement (regra de ouro: preferir adição a modificação), e o risco de
regressão na migração é real. **Gatilho de reavaliação:** se um novo bug de portabilidade escapar
*apesar* da matriz+CI, a reescrita python3 vira o próximo passo (registrar no close-out).

### B. Poda/realinhamento do condutor — **docs + 1 mensagem de hook**

1. `setup-gate.md` §3: o worktree passa a ser criado **preferindo o EnterWorktree nativo**
   (`.claude/worktrees/`), com `superpowers:using-git-worktrees` como fallback; remove a re-especificação
   de mecânica (pasta irmã etc. fica a cargo da skill do superpowers). Mantém o invariante OLI:
   **da `main` atualizada, nunca de outra feature branch** (o token `main` é assert de
   `test_references.sh`).
2. `finalize.md`: mantém os gates OLI (MERGED antes de deletar, PRs stacked, `clean_gone`, close-out);
   **delega a mecânica** de remoção de worktree a `superpowers:finishing-a-development-branch` sem
   duplicar o passo-a-passo (o caveat Windows/junction sai — vive na skill do superpowers).
3. `branch-state-guard.sh:73`: mensagem vira agnóstica de local ("considere um worktree"), sem citar
   caminho. Única mudança em hook do item B; coberta pela suíte (é stderr informativo, não-bloqueio).
4. `SKILL.md` Fase 0: reflete o item 1 (EnterWorktree nativo preferido).

**Não-poda deliberada:** a seção Verification do SKILL.md, os princípios invioláveis e os review gates
ficam — são opinião OLI, não duplicação. Se a poda encontrar pouco além do listado, é isso mesmo
(evidência ou abstenha; não forçar corte).

## Fora de escopo

- Reescrita python3 dos hooks (gatilho acima). — Template `check.sh` para node. — Qualquer mudança de
  comportamento de bloqueio dos hooks. — Renomear hook IDs (regra de ouro #3).

## Critérios de aceite

1. `sh plugins/oli-dev/tests/run_all.sh` → ALL GREEN local (macOS), com os testes de hook executados
   sob `sh`, `bash` e `dash` (dash presente local via `/bin/dash`), e skips anunciados quando faltar shell.
2. `shellcheck` limpo em `plugins/oli-dev/hooks/*.sh` e `plugins/oli-dev/tests/*.sh` (local e CI).
3. Novo job `plugin-tests` verde no self-test (ubuntu) na PR.
4. `test_references.sh` + `test_skill_structure.sh` continuam PASS após a poda (asserts inalterados).
5. Comportamento dos hooks inalterado: os 44 asserts existentes passam sem edição de expectativa
   (exceto o texto da mensagem do guard, se assertado — verificar e ajustar o assert junto).
6. CHANGELOG atualizado no mesmo commit de cada mudança (regra de ouro #5).

## Rastreio

- Análise de origem: sessão 2026-07-02 (efetividade do oli-dev; 6 fixes/8 dias; comparação com skills
  públicas — decisão: manter arquitetura wrapper-fino, endurecer hooks, podar duplicação).
- Adaptação de processo deste ciclo: conductor em **Fable 5** (tier acima do Opus 4.8 exigido pela
  Fase 0 — intenção do gate satisfeita; desvio documentado); brainstorm consolidado da conversa
  (aprovação prévia do usuário) com staff-review cético como gate seguinte.
