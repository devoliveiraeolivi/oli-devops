# Design — `/oli-dev` tier de modelo `light` (oli-dev-light)

**Data:** 2026-06-30 (revisado 2026-07-01)
**Repo alvo:** `oli-devops` — plugin `oli-dev`
**Status:** revisado após staff-review cético + deep-research; **2 tiers (full/light)**; aguardando review do spec revisado.

**Histórico de decisão:** a versão inicial propunha 3 tiers (`low`/`medium`/`high`) com matriz de 7 papéis e pré-flight de triagem. O staff-review (Fase 2) achou um **bloqueio factual**: o conductor não controla o modelo de `/code-review`, `/simplify`, `verify`, `/security-review` (são slash-commands com fleet/modelo próprio; só *effort*, no caso do `/code-review`). Só **2 papéis** são realmente model-controláveis. Uma pesquisa multi-fonte confirmou ainda que (a) tiering por papel é prática publicada mas **a justificativa honesta é custo/latência, não qualidade** (o headline "Opus-orquestrador + Sonnet 90,2%" foi **refutado**), e (b) a camada de orquestração é a de **menor** alavancagem — o verify/gate determinístico é a de maior. Conclusão: **colapsar para 2 tiers** (`full`/`light`), justificados por custo/latência, gates idênticos e enxutos.

---

## 1. Problema e objetivo

Hoje o `/oli-dev` roda **tudo** em Opus 4.8. É o rigor certo para mudança de alto risco, mas caro/lento para mudança pequena/mecânica.

**Objetivo:** um tier opcional **`light`** — o "oli-dev-light" — que roda em **Sonnet 4.6** (`claude-sonnet-4-6`) os **dois únicos papéis cujo modelo o conductor realmente controla** (escritores TDD da Fase 4 e o staff-reviewer da Fase 2), mantendo **tudo o mais idêntico**. O default (`full`) é o comportamento de hoje (tudo Opus).

**Justificativa = custo/latência, não qualidade.** A rede que pega bug é **idêntica** nos dois tiers: conductor sempre Opus (adjudica tudo), `/code-review` roda seu fleet próprio, `verify` roda de verdade, e o **gate determinístico da Fase 6** (lint+test+build) é o backstop model-independent. O `light` só troca o modelo de produção de código + review de spec por Sonnet — onde o ganho de token/latência é real e a rede de segurança continua de pé.

### Não-objetivos (YAGNI — reforçado pela evidência)

- **Não** mexer em `/code-review`, `/simplify`, `verify`, `/security-review` (nem modelo nem effort). São o gate de maior alavancagem; degradá-los seria o oposto do que a evidência recomenda.
- **Não** pular/condensar fase ou gate. `full` e `light` rodam o ciclo completo idêntico.
- **Não** justificar o tier por "mesma qualidade". A aposta declarada é custo/latência com a rede intacta.
- **Não** trocar o modelo do loop principal (conductor sempre Opus; Fase 0 já exige).
- **Não** reintroduzir 3 tiers, matriz de 7 papéis ou pré-flight com rubrica (complexidade que review+pesquisa mandaram cortar).
- **Não** mudar o modo `finalize`.

---

## 2. O que é controlável por tier (a base factual — verificada)

Verificado por leitura do código (`code-review@claude-plugins-official` hardcoda Haiku+5×Sonnet+Haiku e opera sobre PR via `gh`; `/simplify`, `verify`, `/security-review` são built-in sem arquivo de command):

| Papel | Como roda | Tier controla? |
|---|---|---|
| Conductor (loop principal) | modelo da sessão | **Não** — sempre Opus (Fase 0). Cobre brainstorm (F1), plano (F3), adjudicação, e os gates inline `/simplify`/`verify`/`/security-review`, que herdam o Opus do conductor |
| Fase 4 — escritores TDD | `Agent`/subagent-driven-development com `model:` | **SIM (modelo)** |
| Fase 2 — staff-reviewer | `Agent` dispatch com `model:` | **SIM (modelo)** |
| Fase 5 — `/code-review` | slash-command, fleet Haiku+Sonnet próprio | **Não** (nem modelo; só *effort* — que **não** vamos mexer) |

Logo, o único botão honesto do tier é o **modelo dos 2 papéis despachados**. Tudo o mais é invariante.

---

## 3. A matriz (2 tiers)

| Papel | `full` (default) | `light` |
|---|---|---|
| Conductor (+ F1 brainstorm + F3 plano + adjudicação + inline `/simplify` `verify` `/security-review`) | Opus | Opus |
| Fase 5 — `/code-review` (fleet próprio) | inalterado | inalterado |
| Fase 4 — escritores TDD | Opus | **Sonnet** |
| Fase 2 — staff-reviewer (review de spec) | Opus | **Sonnet** |

- **`full`** = comportamento **idêntico ao `/oli-dev` de hoje**.
- **`light`** = escritores TDD + staff-reviewer em Sonnet. O ganho de custo/latência é dominado pelos **escritores TDD** (vários subagentes, várias tasks — o maior sink de tokens); o staff-reviewer é uma passada única (ganho menor, mas grátis).

Concreto na chamada: onde a matriz diz Opus → `model: "opus"`; Sonnet → `model: "sonnet"`.

---

## 4. Invocação e parsing

```
/oli-dev <ideia>          → tier full (default; = hoje)
/oli-dev light <ideia>    → tier light
/oli-dev full <ideia>     → tier full explícito (equivalente ao default)
/oli-dev finalize         → modo finalize (Fase 8), sem tier
```

Regras de parsing (interpretadas pela skill; `$ARGUMENTS` já trimado; comparações **case-insensitive**):

1. Seja `W1` a 1ª palavra separada por espaço.
2. Se `W1` == `finalize` → **modo finalize** (Fase 8). (Match **exato**; muda o `começar com` atual para `==`.)
3. Senão, se `W1` ∈ {`light`, `full`} **E** existe ≥1 palavra depois → tier = `W1`; ideia = o resto.
4. Senão → tier **não** informado (default `full`); ideia = todo o `$ARGUMENTS`.

**Casos de borda resolvidos:**
- `/oli-dev light` (só o token, sem ideia) → regra 3 falha (sem ideia) → cai na regra 4 → ideia = "light", tier full. Como isso é quase certo um erro, a Fase 0 **pede esclarecimento** ("`light` sozinho não é uma ideia — quer `light <ideia>`?").
- **Colisão** (ideia que começa com "light"/"full", ex.: `/oli-dev light refactor of X`): a regra 3 consome "light" como tier. Para tornar visível, a Fase 0 **ecoa a interpretação** antes de agir: *"Interpretei: tier=light, ideia='refactor of X'. Correto?"* — statement de baixa fricção que deixa o misparse óbvio.
- `/oli-dev light finalize` → `W1`="light" (não é finalize) → tier=light, ideia="finalize". A Fase 0 detecta ideia == palavra-modo e pede esclarecimento (não entra em finalize; não roda ciclo com ideia "finalize").

`test_skill_structure.sh` deve passar a distinguir `finalize` de `finalize-xyz` (ver §9).

---

## 5. Piso de segurança (advisory com ack — enxuto)

Sem pré-flight/rubrica. Apenas: se o usuário pedir **`light`** numa mudança que toca **contrato/enforcement** (`policies/ENFORCEMENT.md`, IDs de hook no `.pre-commit-hooks.yaml`, `security.yml` reusável, pins em `common.sh`) **ou superfície sensível** (auth, secrets, SQL/RPC, rede, cripto), a Fase 0 **recomenda `full`** e pede **confirmação explícita** (ack) para seguir em `light`. Respeita "usuário no controle". Como default é `full`, o caminho seguro é o padrão; o `light` é sempre uma escolha deliberada.

Nota: isso é *prior* sobre a ideia. O sub-gate de `/security-review` da Fase 5 continua **independente do tier** e detecta superfície sensível pelo diff de qualquer forma.

---

## 6. Persistência do tier e resume

O tier é decidido na Fase 0. Como o **default é `full` (seguro)**, perder o tier num resume degrada para `full` — nunca para algo mais arriscado. Mesmo assim, para não perder o ganho de custo num ciclo retomado:

- Ao escrever o plano (Fase 3), o conductor **grava o tier no cabeçalho do plano**.
- O passo de resume da Fase 0 (setup-gate) **lê o tier do plano** quando retoma de spec+plano → Fase 4. Ausente/antigo → assume `full` (fallback seguro).
- Antes da Fase 3, o tier vive na memória do conductor e é re-informável; sem perda real (fallback `full`).

---

## 7. Enforcement

Seleção de modelo = **instrução-de-skill** (o conductor despacha os 2 papéis com o `model:` do tier) — mesma classe do "todo subagente Opus" atual. **Critérios observáveis** (não "rodou em Opus", que não dá pra provar em command): o que se verifica é que **o markdown da skill instrui `model:` = X para os 2 papéis despacháveis conforme o tier**, e que os references não se contradizem (§9). Hooks (`branch-state-guard`, `pre-push-gate`) intactos e independentes de tier.

---

## 8. Arquivos afetados

Markdown de skill + parsing do command + 1 teste. **Nenhuma mudança em hook ou `.sh` de produto.**

| Arquivo | Mudança |
|---|---|
| `plugins/oli-dev/commands/oli-dev.md` | Parsing do token `light`/`full` (§4); `finalize` vira match exato; passar modo+tier à skill. |
| `plugins/oli-dev/skills/dev-cycle/SKILL.md` | Reescrever "Princípio 4": escritores TDD + staff-reviewer seguem o tier (full=Opus, light=Sonnet); conductor sempre Opus; `/code-review`/`verify`/`/security-review`/`/simplify` inalterados. Documentar `light` e a base factual (§2). Ajustar *Verification* p/ critério observável (§7). |
| `plugins/oli-dev/skills/dev-cycle/references/model-tiers.md` | **NOVO.** Fonte única: matriz (§3), base factual (§2), justificativa custo/latência, parsing (§4), piso (§5), persistência (§6). Carregado na Fase 0. |
| `plugins/oli-dev/skills/dev-cycle/references/setup-gate.md` | Passo de tier (parsing + eco da interpretação + piso ack + leitura do tier no resume). |
| `plugins/oli-dev/skills/dev-cycle/references/review-gates.md` | Fase 2 staff-reviewer: modelo por tier. Corrigir a frase "todos os subagentes em Opus" da Fase 5 para a realidade (conductor adjudica em Opus; `/code-review` fleet próprio; inline gates herdam Opus). |
| `plugins/oli-dev/README.md` | Documentar `full`/`light` e a base factual. Ajustar a linha "todo review em Opus". |
| `plugins/oli-dev/.claude-plugin/plugin.json` | Ajustar `description` ("Opus nos reviews" → tier). Sem campo `version`. |
| `CHANGELOG.md` | `[Unreleased]` já tem **Fixed** (python + gitignore). Adicionar **Added** (tier `light`) e **Changed** (Princípio 4 redefinido; default segue `full`). Bump **MINOR** v1.2.0 (§10). |
| `plugins/oli-dev/tests/test_references.sh` | Reescrever a asserção `grep -qi 'opus'` (linha 12) para checar a invariante nova (ver §9). |
| `plugins/oli-dev/tests/test_skill_structure.sh` (ou novo) | Assert de parsing: reconhece `light`/`full`, distingue `finalize` de `finalize-xyz`. |
| `plugins/oli-dev/evals/evals.json` | Ajustar/estender: o eval que ancora "Opus em todo subagente" deve refletir "conductor sempre Opus; papéis despacháveis seguem o tier". |

---

## 9. Testes (critérios observáveis)

Shell asserts, estilo dos `tests/*.sh` atuais:

1. `references/model-tiers.md` existe, não-vazio, menciona `full` e `light`.
2. `model-tiers.md` afirma **conductor sempre Opus** e marca **`/code-review`, `verify`, `/security-review` como não-controlados pelo tier**.
3. **Reescrever `test_references.sh:12`**: em vez do `grep -qi 'opus'` genérico, checar que `review-gates.md` documenta a adjudicação Opus do conductor **e** que aponta a matriz do tier (sem afirmar "todos os subagentes em Opus", que é falso).
4. `setup-gate.md` contém o passo de tier (parsing + resume do tier).
5. **Parsing:** `commands/oli-dev.md` reconhece `light`/`full`; distingue `finalize` de `finalize-xyz` (match exato).
6. `tests/run_all.sh` verde (inclui os 2 fixes de infra já commitados).

TDD: teste antes do conteúdo, conforme o próprio ciclo.

---

## 10. Versionamento e CHANGELOG

Aditivo e retrocompatível (novo flag opcional; default = hoje; nenhum hook ID mexido; nenhuma fase alterada) → **MINOR**, v1.1.1 → **v1.2.0** ([SEMVER](../../../policies/SEMVER.md)).

`[Unreleased]` **já contém `Fixed`** (portabilidade python3 + gitignore `.claude/worktrees/`, commitados neste worktree). O v1.2.0 sai carregando três seções, honestamente separadas:
- **Fixed** — os 2 fixes de infra (já lá).
- **Added** — tier `light` (`/oli-dev light <ideia>`): escritores TDD + staff-reviewer em Sonnet; default `full` inalterado.
- **Changed** — "Princípio 4" redefinido de "todo subagente em Opus" para "conductor sempre Opus; papéis despacháveis seguem o tier"; apontar que `/oli-dev <ideia>` sem tier continua full-Opus.

Não toca `policies/ENFORCEMENT.md` (processo interno de dev ≠ matriz de enforcement dos consumidores) → não é MAJOR.

---

## 11. Riscos e mitigações

| Risco | Mitigação |
|---|---|
| Sonnet-escritor introduz bug no `light` | Rede idêntica ao `full`: `/code-review` (fleet próprio), `verify`, gate determinístico da Fase 6, conductor Opus adjudicando; TDD escreve teste antes. |
| Mudança de contrato/sensível rodada em `light` | Piso advisory com ack (§5); default é `full`, então `light` é sempre deliberado. |
| Ganho de custo do `light` ser pequeno | O ganho vem dos escritores TDD (maior sink), não do staff-reviewer; é real. Se num ciclo os escritores forem poucos, o `light` rende pouco — aceitável (é opt-in). |
| Tier perdido no resume | Default `full` (fallback seguro); tier gravado no cabeçalho do plano e lido no resume (§6). |
| Deriva entre matriz e reviews | Fonte única em `model-tiers.md`; `review-gates.md` referencia; teste cruzado (§9.3). |
| Expectativa de full-Opus surpreendida | Default **é** full-Opus (sem surpresa); `light` é opt-in explícito; nota `Changed` no CHANGELOG. |

---

## 12. Critérios de aceite (DoD)

1. `/oli-dev <ideia>` e `/oli-dev full <ideia>` → comportamento **idêntico** ao de hoje (escritores TDD + staff-reviewer em Opus).
2. `/oli-dev light <ideia>` → a skill instrui despachar escritores TDD (F4) e staff-reviewer (F2) com `model: "sonnet"`; conductor, `/code-review`, `verify`, `/security-review` inalterados.
3. Parsing: `finalize` exato; `light`/`full` reconhecidos só como 1ª palavra + ideia; eco da interpretação em colisão; esclarecimento em `light` sozinho / `light finalize`.
4. `light` + contrato/sensível → aviso de piso com ack (§5).
5. Resume lê o tier do plano; ausente → `full`.
6. `finalize` inalterado; fases/gates idênticos nos dois tiers.
7. `tests/run_all.sh` verde; `test_references.sh:12` reescrito; teste de parsing presente; CHANGELOG com Fixed+Added+Changed; MINOR.

---

## Apêndice A — Rastreio dos achados do staff-review → resolução

- **#1 (BLOQUEIA) premissa de model-control falsa** → resolvido: matriz reduzida aos 2 papéis controláveis; `/code-review` etc. explicitamente fora do tier (§2, §3).
- **#2 (BLOQUEIA) enforcement inverificável / grep 'opus'** → critério observável (§7) + reescrita de `test_references.sh:12` (§9.3).
- **#3 parsing ambíguo** → regras exatas + colisão + eco + `finalize` exact-match (§4).
- **#4 escopo dos fixes de infra** → reconhecido `[Unreleased]/Fixed`; bundle honesto Fixed+Added+Changed em v1.2.0 (§10).
- **#5 persistência/resume** → tier no cabeçalho do plano + fallback `full` (§6).
- **#6 YAGNI do 3º tier** → resolvido colapsando para 2 tiers.
- **#7 golden rules / nota Changed** → seção `Changed` no CHANGELOG + update do eval (§8, §10).

## Apêndice B — O que a deep-research mudou

- Tiering por papel **é** prática publicada (TDFlow, EACL 2026), mas a justificativa vira **custo/latência**; o headline first-party "90,2%" foi **refutado** → não usar como justificativa.
- Camada de orquestração é a de **menor** alavancagem; verify/gate determinístico é a de **maior** → manter gates enxutos e **não** degradar `/code-review`/`verify` no `light`.
- Muito já vem "de fábrica" (Claude Code: subagentes, plan mode, `/code-review`, review adversarial) → o valor do `oli-dev` é a **cola de política** (baseline de segurança, `gh`/PR, hook de pre-push determinístico, finalize), não os primitivos.
