# Design — `/oli-dev` tiers de modelo (`low`/`medium`/`high`) com pré-flight de triagem

**Data:** 2026-06-30
**Repo alvo:** `oli-devops` — plugin `oli-dev`
**Status:** spec aprovado em brainstorming, aguardando review do usuário
**Supersede parcial:** ajusta o "Princípio 4" do plugin (`2026-06-24-oli-dev-plugin-design.md`)
— de *"todo subagente sempre em Opus"* para *"o modelo do subagente segue a matriz do tier;
os pilares de julgamento são sempre Opus"*.

---

## 1. Problema e objetivo

Hoje o `/oli-dev` roda **tudo** em Opus 4.8: o loop principal (conductor) e **todos** os
subagentes — escritores TDD (Fase 4) e reviewers (Fases 2/5). É o nível certo de rigor para
mudanças de alto risco, mas é caro e lento para mudanças pequenas/mecânicas, onde o Opus em
todo papel é desperdício.

**Objetivo:** adicionar um eixo de **tier de modelo** ao `/oli-dev` — `low` / `medium` /
`high` — que escolhe, **por papel**, se o subagente roda em **Sonnet 4.6** (`claude-sonnet-4-6`)
ou **Opus 4.8** (`claude-opus-4-8`). Quanto mais baixo o tier, mais papéis "ágeis" caem para
Sonnet; o `high` mantém o comportamento atual (tudo Opus). Um **pré-flight de triagem** na
Fase 0 sugere o tier a partir da ideia, e o usuário confirma ou troca.

O tier muda **apenas o modelo por papel**. **Não** muda fases, gates, ordem, nem enforcement.
Num repo que é baseline de segurança ("toda mudança é de alta alavancagem, todo bug é
amplificado"), os gates *são* o produto: removê-los seria perda qualitativa de rede de
segurança; trocar o modelo é trocar profundidade por velocidade/custo mantendo as mesmas
checagens rodando.

### Não-objetivos (YAGNI)

- **Não** pular, condensar ou tornar opcional nenhuma fase ou gate. Os três tiers rodam o
  ciclo completo idêntico.
- **Não** mexer no loop principal: o conductor é sempre Opus em todos os tiers (a Fase 0 já
  exige isso e continua exigindo).
- **Não** tornar a seleção de modelo um hook determinístico. Continua sendo instrução-de-skill
  (mesma classe de enforcement do "todo subagente Opus" de hoje).
- **Não** adicionar campo `version` ao `plugin.json` (não existe hoje; versionamento é no nível
  do repo via CHANGELOG + tags).
- **Não** mudar o modo `finalize` (Fase 8 não tem tier nem pré-flight — é só limpeza).

---

## 2. Conceito: o tier é um botão de modelo por papel

O ciclo tem dois tipos de trabalho com modelo distinto:

1. **Trabalho do loop principal (conductor):** Fase 1 brainstorm e Fase 3 plano rodam **no
   próprio conductor**, não em subagente. Como o conductor é sempre Opus, **brainstorm e
   plano são sempre Opus em todos os tiers** — não há botão de tier para eles.
2. **Subagentes despachados:** Fase 2 (staff-reviewer), Fase 4 (escritores TDD), Fase 5
   (`/code-review`, `/simplify`, `verify`, `/security-review` condicional). O tier escolhe o
   modelo de cada um destes.

### 2.1 Princípio dos três pilares (a regra mental)

> **Planejar, caçar bug e segurança são sempre Opus.** O resto — *produzir código*,
> *revisão mole* e *verificação observacional* — desce para Sonnet nos tiers light, com o
> **gate determinístico da Fase 6** (pre-push: lint+test+build) como backstop
> model-independent de "testes verdes".

Os três pilares que **nunca degradam** (Opus em qualquer tier):

- **Planejar** — o conductor: brainstorm (Fase 1) + plano (Fase 3) + adjudicação dos achados
  do `/simplify` e dos gates. Um plano ruim amplifica em código ruim do começo ao fim — é o
  lugar mais caro para economizar.
- **Caçar bug** — `/code-review` (Fase 5). É a rede que pega os erros do escritor-Sonnet;
  degradá-la anularia o ganho de pôr o escritor em Sonnet.
- **Segurança** — `/security-review` (sub-gate condicional da Fase 5). Superfície sensível
  (auth, secrets, SQL/RPC, rede, cripto) não negocia modelo.

### 2.2 Por que `verify` pode ser Sonnet nos tiers light

`verify` (Fase 5) **não** é o enforcer final de "testes verdes" — quem é, é a **Fase 6**, um
hook determinístico (`hooks/pre-push-gate.sh`) que roda `black+ruff+pytest+mypy` (ou
lint+test+build) **independente de modelo, em todos os tiers**, e bloqueia push quebrado. O
`verify` da Fase 5 é a passada *observacional* (rodar testes/app e olhar o comportamento) —
executar-e-observar, não caçar bug sutil. Com o backstop determinístico da Fase 6 + o
`/code-review` em Opus, o `verify` pode ser Sonnet no `low`/`medium` sem furar a rede. O que
se perde no `medium` é o juízo *end-to-end* mais afiado ("os testes passam mas o output está
sutilmente errado"), aceitável para um tier light por causa desse duplo backstop.

---

## 3. A matriz de modelos (fonte única de verdade)

| Papel | `low` | `medium` | `high` |
|---|---|---|---|
| Conductor **+ Fase 1 brainstorm + Fase 3 plano** | Opus | Opus | Opus |
| Fase 5 — `/code-review` | Opus | Opus | Opus |
| Fase 5 — `/security-review` (condicional) | Opus | Opus | Opus |
| Fase 4 — escritores TDD | **Sonnet** | **Sonnet** | Opus |
| Fase 5 — `verify` | **Sonnet** | **Sonnet** | Opus |
| Fase 2 — staff-reviewer (review de spec) | **Sonnet** | Opus | Opus |
| Fase 5 — `/simplify` | **Sonnet** | Opus | Opus |

Leitura por tier:

- **`high`** — nada em Sonnet. Rigor máximo. **Comportamento idêntico ao `/oli-dev` de hoje.**
- **`medium`** — escritores TDD + `verify` em Sonnet; bug-review, security, simplify,
  spec-review e plano em Opus. O ponto-doce: acelera o maior sink de tokens (escritores) e a
  verificação observacional, mantendo toda a revisão de julgamento em Opus.
- **`low`** — também o staff-reviewer (spec) e o `/simplify` em Sonnet. A rede dura (planejar,
  caçar bug, segurança) segue Opus.

Os três tiers são distintos por construção: `medium` adiciona escritores + verify em Sonnet
sobre o `high`; `low` adiciona staff-reviewer + simplify sobre o `medium`. O delta de custo é
real mesmo o `low` mexendo em poucos papéis, porque os escritores são vários subagentes em
várias tasks — é onde o token pesa; spec-review e simplify são passadas únicas.

**Modelo concreto na chamada de subagente:** onde a matriz diz Opus → `model: "opus"`; onde
diz Sonnet → `model: "sonnet"`. Effort alto continua o default nos papéis de review.

---

## 4. Pré-flight de triagem (novo passo no topo da Fase 0)

Roda **apenas no modo ciclo** (não em `finalize`). A **sugestão** de tier só acontece quando o
tier não foi passado explicitamente; o **piso de segurança (§5)** é verificado nos dois casos
(tier explícito *ou* sugerido).

### 4.1 Fluxo

- `/oli-dev low|medium|high <ideia>` → tier explícito: pré-flight **não sugere** (usuário já
  decidiu); aplica só o piso de segurança da seção 5.
- `/oli-dev <ideia>` (sem tier) → o conductor (Opus) classifica a ideia pela rubrica abaixo,
  **sugere** um tier com 1–2 linhas de justificativa, e **pede confirmação**. O usuário aceita
  ou troca. Se o usuário não engajar / aceitar a sugestão, vale a sugestão; o fallback seguro
  em caso de dúvida do classificador é `high`.

### 4.2 Rubrica (curta e decisiva)

| Sinal na ideia | Sugere |
|---|---|
| Mexe no **contrato público / enforcement**: `policies/ENFORCEMENT.md`, IDs de hook no `.pre-commit-hooks.yaml`, `.github/workflows/security.yml` (reusável), pins em `scripts/common.sh`; **ou superfície sensível** (auth, secrets/`.env`, SQL/RPC, rede/HTTP, credenciais, cripto); **ou território de MAJOR** (pode quebrar consumidor que passa hoje) | **`high`** |
| Trabalho normal de feature; hook/script novo e autocontido com testes; raio de impacto limitado | **`medium`** |
| Localizado e mecânico: docs, 1 fixture, ajuste de texto em template, mudança só-de-teste, script autocontido com testes fortes; território de PATCH | **`low`** |

A rubrica opera sobre a **descrição da ideia** (e, se a ideia citar paths concretos, uma
varredura rápida deles). O sinal mais rico — o diff de fato tocando superfície sensível — só
existe na Fase 5; o **sub-gate de `/security-review` da Fase 5 continua independente do tier**
e detecta superfície sensível pelo diff de qualquer forma. O pré-flight é um *prior*; o
sub-gate da Fase 5 é a rede baseada no diff.

---

## 5. Piso de segurança (advisório com ack)

Quando a ideia bate nos sinais de `high` da rubrica (contrato/enforcement/sensível) **mas** o
tier pedido (explícito ou sugerido/aceito) é **abaixo de `high`**:

- O pré-flight **recomenda `high`** e avisa, alto, o porquê (1 linha citando o sinal).
- O usuário pode **descer mesmo assim com uma confirmação explícita** (ack). Respeita o
  princípio "usuário no controle" do superpowers, mantendo o risco barulhento.
- **Independente do ack, os três pilares seguem Opus** — em particular, se a mudança é de
  superfície sensível, o `/security-review` roda em Opus de qualquer jeito (matriz, seção 3),
  e o `/code-review` também (sempre Opus). Ou seja: mesmo num `low` "forçado", a rede que
  importa para uma mudança de contrato não está em Sonnet.

Isto **não** é um piso duro (não força `high` sem override) — é a opção "advisório com ack"
aprovada no brainstorming.

---

## 6. Invocação e parsing do command

`commands/oli-dev.md` passa a reconhecer um **token de tier opcional** como primeira palavra
de `$ARGUMENTS`:

```
/oli-dev <ideia>                 → modo ciclo, tier não informado → pré-flight sugere
/oli-dev low|medium|high <ideia> → modo ciclo, tier explícito → pula sugestão (aplica piso §5)
/oli-dev finalize                → modo finalize (Fase 8), sem tier, sem pré-flight
```

Regras de parsing (no markdown do command, interpretadas pela skill):

- Se a 1ª palavra de `$ARGUMENTS` for exatamente `finalize` → modo finalize.
- Senão, se a 1ª palavra for exatamente `low`, `medium` ou `high` (case-insensitive) → esse é
  o tier; o resto é a ideia.
- Senão → tier não informado (pré-flight decide); todo o `$ARGUMENTS` é a ideia.

**Retrocompat:** a interface `/oli-dev <ideia>` não quebra. Muda apenas que, sem tier, ela
agora **pergunta** (via pré-flight) em vez de assumir full-Opus silenciosamente. Quem quer o
comportamento antigo determinístico usa `/oli-dev high <ideia>`.

---

## 7. Enforcement

A seleção de modelo é **instrução-de-skill** — o conductor (Opus) despacha cada subagente com
o `model:` da matriz. É a **mesma classe de enforcement** do atual "todo subagente em Opus"
(que também é instrução, não hook). Os hooks existentes ficam **intactos** e independentes de
tier:

- `hooks/branch-state-guard.sh` — bloqueia commit/push em branch já MERGED.
- `hooks/pre-push-gate.sh` — backstop determinístico de lint+test+build na Fase 6.

O backstop da Fase 6 é o que sustenta o `verify` em Sonnet (seção 2.2): "testes verdes" é
garantido por shell, não pelo modelo.

---

## 8. Arquivos afetados

Tudo é markdown de skill + parsing do command. **Nenhuma mudança em hook ou script `.sh`.**

| Arquivo | Mudança |
|---|---|
| `plugins/oli-dev/commands/oli-dev.md` | Parsear o token de tier opcional (§6); passar o modo+tier para a skill. |
| `plugins/oli-dev/skills/dev-cycle/SKILL.md` | Reescrever o "Princípio 4" para a regra dos três pilares; documentar os tiers e o pré-flight; apontar para o novo reference. Atualizar a seção *Verification* para checar o modelo por papel conforme o tier. |
| `plugins/oli-dev/skills/dev-cycle/references/model-tiers.md` | **NOVO.** Fonte única: a matriz (§3), o princípio dos três pilares, a rubrica do pré-flight (§4) e o piso de segurança (§5). Carregado na Fase 0 (progressive disclosure). |
| `plugins/oli-dev/skills/dev-cycle/references/setup-gate.md` | Adicionar o passo de **pré-flight de triagem** no topo (antes da checagem de modelo do loop), com ponteiro para `model-tiers.md`. |
| `plugins/oli-dev/skills/dev-cycle/references/review-gates.md` | Fases 2 e 5 deixam de dizer "sempre Opus" e passam a referenciar a matriz do tier (com os pilares `/code-review` e `/security-review` marcados como sempre-Opus). |
| `plugins/oli-dev/README.md` | Documentar os três tiers, a matriz e o pré-flight no "Uso". Ajustar a linha que afirma "todo review em Opus". |
| `plugins/oli-dev/.claude-plugin/plugin.json` | Ajustar a `description` (hoje diz "Opus nos reviews") para refletir os tiers. (Sem campo `version`.) |
| `CHANGELOG.md` | Entrada `## [Unreleased]` → `### Added` documentando os tiers + pré-flight (bump **MINOR**, §10). |
| `plugins/oli-dev/tests/*.sh` | Cobrir o novo reference e a consistência da matriz (§9). |
| `plugins/oli-dev/evals/evals.json` | *(opcional)* eval de seleção de tier pelo pré-flight. Fora do escopo mínimo; registrar como follow-up se não couber. |

---

## 9. Testes

Testes são shell asserts sobre o conteúdo dos markdowns (estilo dos `tests/*.sh` existentes —
`test_references.sh`, `test_skill_structure.sh`, `test_manifests.sh`):

1. **Existência do reference:** `references/model-tiers.md` existe e é não-vazio.
2. **Os três tiers documentados:** o reference menciona `low`, `medium` e `high`.
3. **Os três pilares sempre-Opus:** o reference afirma conductor/plano, `/code-review` e
   `/security-review` como sempre Opus.
4. **Consistência cruzada:** `setup-gate.md` contém o passo de pré-flight; `review-gates.md`
   referencia a matriz e não contradiz a matriz (não afirma "sempre Opus" para papéis que a
   matriz põe em Sonnet).
5. **Parsing do command:** `commands/oli-dev.md` reconhece os tokens `low|medium|high` e
   preserva o caminho `finalize`.
6. **Regressão de referências:** `test_references.sh` continua verde (links/paths válidos).

`tests/run_all.sh` deve continuar verde. O ciclo se desenvolve em TDD (testes antes do
conteúdo) conforme a Fase 4 do próprio `/oli-dev`.

---

## 10. Versionamento e CHANGELOG

Mudança **aditiva** e **retrocompatível**: novo eixo opcional (tier), default preserva a
interface; nenhum hook ID renomeado/removido; nenhuma fase/gate alterada. Por
[`policies/SEMVER.md`](../../../policies/SEMVER.md) → **MINOR** (de `v1.1.1` para `v1.2.0`).

Golden rule #5 (CLAUDE.md): CHANGELOG no **mesmo commit** da mudança. Entrada em
`## [Unreleased] / ### Added` descrevendo os tiers, a matriz e o pré-flight, e deixando claro
que `high` == comportamento anterior.

> Nota: não toca `policies/ENFORCEMENT.md` (matriz de segurança dos consumidores) — isto é o
> processo *interno* de dev, não a política de enforcement dos repos consumidores. Logo, não é
> um MAJOR pela regra da matriz de enforcement.

---

## 11. Riscos e mitigações

| Risco | Mitigação |
|---|---|
| Sonnet-escritor introduz bug que o tier light não pega | `/code-review` é **sempre Opus** (pilar); Fase 6 (hook determinístico) bloqueia testes quebrados; TDD escreve teste antes do código. |
| Mudança de contrato roda em tier baixo por engano | Pré-flight recomenda `high` com ack barulhento (§5); `/security-review` e `/code-review` seguem Opus mesmo num `low` forçado. |
| `low` e `medium` virarem indistinguíveis | Matriz desenhada para deltas claros: `medium` = +escritores +verify; `low` = +staff-reviewer +simplify. Teste de consistência (§9) trava a matriz. |
| Deriva entre a matriz e os reviews nas Fases 2/5 | Fonte única em `model-tiers.md`; `review-gates.md` referencia, não duplica; teste cruzado (§9.4). |
| Usuário espera full-Opus em `/oli-dev <ideia>` e é surpreendido pelo pré-flight | Pré-flight é explícito e pede confirmação (não baixa silenciosamente); `high` documentado como o caminho determinístico. |

---

## 12. Critérios de aceite (DoD)

1. `/oli-dev high <ideia>` produz comportamento **idêntico** ao `/oli-dev <ideia>` de hoje
   (todos os subagentes em Opus).
2. `/oli-dev medium <ideia>` roda escritores TDD e `verify` em Sonnet; staff-reviewer,
   `/simplify`, `/code-review`, `/security-review` e plano em Opus.
3. `/oli-dev low <ideia>` adiciona staff-reviewer e `/simplify` em Sonnet; pilares (plano,
   `/code-review`, `/security-review`) seguem Opus.
4. `/oli-dev <ideia>` (sem tier) dispara o pré-flight, que sugere um tier com justificativa e
   pede confirmação.
5. Ideia que toca contrato/enforcement/sensível + tier < `high` → aviso de piso com ack (§5).
6. `finalize` inalterado (sem tier, sem pré-flight).
7. Todas as fases e gates rodam idênticos nos três tiers (nada pulado).
8. `tests/run_all.sh` verde; CHANGELOG atualizado no mesmo commit; bump MINOR.
