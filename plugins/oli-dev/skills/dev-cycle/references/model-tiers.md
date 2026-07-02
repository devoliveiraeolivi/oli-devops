# Tiers de modelo — `full` (default) e `light`

Fonte única do tier de modelo do `/oli-dev`. Carregada na Fase 0.

## Princípio (o que o tier muda — e o que NÃO muda)

O tier troca **apenas o modelo dos dois papéis cujo modelo o conductor realmente
controla** — os **escritores TDD (Fase 4)** e o **staff-reviewer (Fase 2)**, ambos
despachados via `Agent`/`subagent-driven-development` com `model:` explícito.

Escopo desta matriz: **modelo, e só modelo**. Integrações ambientes opcionais condicionadas
ao tier (quando presentes na sessão) vivem na **Fase 0** — ver `setup-gate.md`, passo 7 —
e não entram nesta fonte única.

**Justificativa = custo/latência, não qualidade.** A rede que pega bug é **idêntica**
nos dois tiers. Não use o tier como se fosse "mesma qualidade mais barato" — a aposta
honesta é: onde a produção de código pode ir pra Sonnet, o ganho de token/latência é
real e a rede de segurança continua de pé.

## O que é (e não é) controlável por tier

| Papel | Como roda | Tier controla? |
|---|---|---|
| **Conductor** (loop principal) | modelo da sessão | **Não** — sempre Opus (Fase 0). Cobre brainstorm (F1), plano (F3), adjudicação, e os gates inline `/simplify` · `verify` · `/security-review`, que herdam o Opus do conductor |
| **Escritores TDD** (Fase 4) | `Agent` / subagent-driven-development, `model:` | **SIM — modelo** |
| **Staff-reviewer** (Fase 2) | `Agent` dispatch, `model:` | **SIM — modelo** |
| **`/code-review`** (Fase 5) | slash-command, fleet Haiku+Sonnet próprio | **Não** (nem modelo; nem mexemos no effort) |

Base factual (verificada): `/code-review` é um command que define o próprio fleet e opera
sobre o diff/PR — o conductor não passa `model:` pra ele. `/simplify`, `verify`,
`/security-review` são built-in e rodam no contexto do conductor (Opus). Logo o único
botão honesto do tier é o **modelo dos 2 papéis despachados**.

## A matriz

| Papel | `full` (default) | `light` |
|---|---|---|
| Conductor (+ F1 brainstorm + F3 plano + adjudicação + inline `/simplify` `verify` `/security-review`) | Opus | Opus |
| Fase 5 — `/code-review` (fleet próprio) | inalterado | inalterado |
| Fase 4 — escritores TDD | Opus | **Sonnet** (`model: "sonnet"`) |
| Fase 2 — staff-reviewer | Opus | **Sonnet** (`model: "sonnet"`) |

- **`full`** = comportamento idêntico ao `/oli-dev` de hoje (tudo Opus).
- **`light`** = escritores TDD + staff-reviewer em Sonnet 4.6. O ganho vem sobretudo dos
  **escritores** (vários subagentes, várias tasks — o maior sink de tokens).

## Invocação e parsing

```
/oli-dev <ideia>          → tier full (default; = hoje)
/oli-dev light <ideia>    → tier light
/oli-dev full <ideia>     → tier full explícito
/oli-dev finalize         → modo finalize (Fase 8), sem tier
```

Regras (comparações **case-insensitive**; `$ARGUMENTS` já trimado; `W1` = 1ª palavra):

1. `W1` == `finalize` (match **exato**) → modo finalize (Fase 8).
2. Senão, `W1` ∈ {`light`, `full`} **E** existe ≥1 palavra depois → tier = `W1`; ideia = o resto.
3. Senão → tier não informado (default **`full`**); ideia = todo o `$ARGUMENTS`.

Casos de borda:
- **Eco da interpretação:** ao reconhecer um tier explícito, a Fase 0 **anuncia** *"Interpretei:
  tier=`<t>`, ideia='`<...>`'"* antes de agir — deixa visível uma colisão (ex.: ideia que
  começa com a palavra "light"/"full").
- `/oli-dev light` (só o token, sem ideia) ou `/oli-dev light finalize` → **peça
  esclarecimento**; não rode um ciclo com ideia vazia nem com a ideia == palavra-modo.

## Piso de segurança (advisory com ack)

Se o usuário pedir **`light`** numa mudança que toca **contrato/enforcement**
(`policies/ENFORCEMENT.md`, IDs de hook no `.pre-commit-hooks.yaml`, `security.yml`
reusável, pins em `common.sh`) **ou superfície sensível** (auth, secrets, SQL/RPC, rede,
cripto): **recomende `full`** e peça **confirmação explícita** (ack) para seguir em `light`.
Como o default é `full`, o caminho seguro é o padrão e o `light` é sempre deliberado.
(Isto é *prior* sobre a ideia; o sub-gate de `/security-review` na Fase 5 continua
independente do tier e detecta superfície sensível pelo diff.)

## Persistência do tier (resume)

O default `full` é o fallback seguro — perder o tier num resume degrada para `full`,
nunca para algo mais arriscado. Para não perder o ganho num ciclo retomado:
- Ao escrever o plano (Fase 3), **grave o tier no cabeçalho do plano**.
- O resume da Fase 0 (`setup-gate.md`) **lê o tier do plano** ao retomar de spec+plano → Fase 4.
  Ausente/antigo → assuma **`full`**.
