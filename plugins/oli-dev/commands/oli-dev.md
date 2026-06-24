<!-- plugins/oli-dev/commands/oli-dev.md -->
---
name: oli-dev
description: Roda o ciclo de desenvolvimento OLI (worktree → brainstorm → review → plano → escrita TDD → review → pre-push → PR). Use `/oli-dev <ideia>` para iniciar o ciclo, ou `/oli-dev finalize` para a limpeza pós-merge.
---

Argumentos recebidos: `$ARGUMENTS`

Invoque a skill `dev-cycle` (plugin oli-dev) e siga-a à risca.

- Se `$ARGUMENTS` começar com `finalize` → modo **finalize** (apenas Fase 8: close-out + limpeza pós-merge).
- Caso contrário, trate `$ARGUMENTS` como a descrição da feature → modo **ciclo** (Fases 0–7).

Não pule fases nem gates. Os 4 Princípios de processo do spec são invioláveis.
