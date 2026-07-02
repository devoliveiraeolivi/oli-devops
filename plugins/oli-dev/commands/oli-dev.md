---
name: oli-dev
description: Roda o ciclo de desenvolvimento OLI (worktree → brainstorm → review → plano → escrita TDD → review → pre-push → PR). Use `/oli-dev [light] <ideia>` para iniciar o ciclo (tier `full` default; `light` = escritores TDD + staff-reviewer em Sonnet), ou `/oli-dev finalize` para a limpeza pós-merge.
---

Argumentos recebidos: `$ARGUMENTS`

Invoque a skill `dev-cycle` (plugin oli-dev) e siga-a à risca. Faça o parsing de `$ARGUMENTS`
(case-insensitive; `W1` = primeira palavra):

1. Se `W1` == `finalize` (match **exato**, não "começa com") → modo **finalize** (apenas Fase 8:
   close-out + limpeza pós-merge).
2. Senão, se `W1` ∈ {`light`, `full`} **e** houver ≥1 palavra depois → **tier** = `W1` e a
   **ideia** é o resto → modo **ciclo** (Fases 0–7).
3. Senão → tier não informado (default **`full`**); toda a `$ARGUMENTS` é a ideia → modo **ciclo**.

O tier só troca o modelo dos escritores TDD (Fase 4) e do staff-reviewer (Fase 2): `full` = Opus
(default, = hoje), `light` = Sonnet. Conductor sempre Opus; `/code-review`, `verify`,
`/security-review` inalterados. Detalhes: `references/model-tiers.md`.
Com o plugin ponytail presente na sessão, o tier `light` também ativa `/ponytail lite` na Fase 0
(opcional, fail-open — ver `references/setup-gate.md`, passo 7).

Não pule fases nem gates. Os Princípios de processo do spec são invioláveis.
