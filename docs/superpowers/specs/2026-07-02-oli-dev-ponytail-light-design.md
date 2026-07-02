# oli-dev: ativação condicional do ponytail no tier `light`

**Data:** 2026-07-02 · **Tier do ciclo:** light · **Origem:** avaliação do plugin ponytail
(DietrichGebert/ponytail) na sessão de 2026-07-02; usuário aprovou "preparar a fatia".

## Problema

O usuário quer trial do ponytail (pressão anti-over-engineering ambiente, modo `lite`) **acoplado ao
tier `light` do /oli-dev**, sem ligar o ponytail no resto das sessões (default global `off` no
`~/.config/ponytail/config.json`). Hoje a ativação é manual (`/ponytail lite` por sessão) — fácil de
esquecer e sem evidência registrada no ciclo.

## Decisão

Mudança **docs-only do condutor** (nenhum hook tocado):

1. **`references/setup-gate.md`** — novo passo 7, após o passo 6 (tier):
   - Se tier=`light` **e** o plugin ponytail está disponível na sessão → invocar `/ponytail lite` e
     **colar o output** confirmando o nível (evidência, não alegação).
   - Se tier=`full` **e** o ponytail está disponível → garantir `/ponytail off` (não poluir o full).
   - **Ponytail ausente → seguir sem ele, anunciando** ("ponytail ausente — tier light segue sem
     pressão ambiente"). Dependência OPCIONAL: ausência NUNCA bloqueia o ciclo (mesma filosofia
     fail-open do gate).
   - Nota no passo: o alcance da injeção ambiente nos **subagentes despachados** (escritores TDD)
     não está verificado — no 1º ciclo light com ponytail ativo, verificar e registrar no close-out.
2. **`references/model-tiers.md`** — na descrição do tier `light`, uma linha: light também ativa
   `/ponytail lite` quando o plugin está presente (parte da postura custo/lean do tier); `full` não.
3. **`SKILL.md`** — bullet da Fase 0 ganha "+ ponytail por tier (opcional)".
4. **`tests/test_references.sh`** — 1 assert novo: `setup-gate.md` e `model-tiers.md` mencionam
   `ponytail` (trava contra remoção acidental do passo; dá o RED→GREEN da fatia).
5. **CHANGELOG** — `[Unreleased]` → `### Added`, mesmo commit.

## Fora de escopo

- Instalar/configurar o ponytail (ação do usuário; o passo é condicional à presença).
- Injetar o ladder do ponytail nos prompts de despacho dos writers (seria replicar o plugin;
  só reavaliar depois do resultado do trial — ver nota do passo 7).
- Qualquer mudança em hooks/ ou no comportamento de enforcement.

## Critérios de aceite

1. `sh plugins/oli-dev/tests/run_all.sh` → ALL GREEN (incluindo o assert novo).
2. O texto do passo 7 não deixa ambiguidade nos 3 ramos (light+presente / full+presente / ausente).
3. Invariantes preservados: tokens `main` (setup-gate.md) e asserts existentes intactos.
4. CHANGELOG no mesmo commit.
