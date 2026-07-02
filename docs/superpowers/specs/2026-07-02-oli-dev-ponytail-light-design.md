# oli-dev: ativação condicional do ponytail no tier `light`

**Data:** 2026-07-02 · **Tier do ciclo:** light · **Origem:** avaliação do plugin ponytail
(DietrichGebert/ponytail) na sessão de 2026-07-02; usuário aprovou "preparar a fatia".

## Problema

O usuário quer trial do ponytail (pressão anti-over-engineering ambiente, modo `lite`) **acoplado ao
tier `light` do /oli-dev**, sem ligar o ponytail no resto das sessões (default global `off` no
`~/.config/ponytail/config.json`). Hoje a ativação é manual (`/ponytail lite` por sessão) — fácil de
esquecer e sem evidência registrada no ciclo.

## Decisão (pós staff-review — 2 bloqueios resolvidos)

Mudança **docs-only do condutor** (nenhum hook tocado). Incorporações do staff-review: `full` não
toca no ponytail (over-reach removido → sem save/restore); ponytail fora do `model-tiers.md` (o
princípio "o tier troca apenas o modelo" fica intacto); detecção e evidência operacionalizadas.

1. **`references/setup-gate.md`** — novo passo 7, após o passo 6 (tier), com 3 ramos não-ambíguos:
   - **Detecção**: "disponível" = o comando `/ponytail` aparece entre os comandos/skills da sessão
     (mesmo mecanismo do passo 2). Se invocado e o host responder comando desconhecido/erro →
     tratar como ausente (fail-open).
   - **tier=`light` + disponível** → invocar `/ponytail lite`; **evidência** = output da invocação
     ou, se não houver texto capturável, `/ponytail` sem argumento (reporta o nível) — colar um dos
     dois. Se nenhum produzir texto → anunciar "sem output capturável" e seguir (dependência
     opcional; registrado na PR).
   - **tier=`full`** → **não tocar no ponytail** (não ligar ≠ desligar: se o usuário o ligou
     globalmente por escolha própria, o ciclo não sobrescreve). O modo per-session do ponytail não
     persiste entre sessões (README: "disables... for that session only"; ⚠️ não verificado
     localmente — validar no 1º ciclo do trial).
   - **Ausente (qualquer tier)** → anunciar e seguir. Ausência NUNCA bloqueia (fail-open).
   - Nota no passo: o alcance da injeção ambiente nos **subagentes despachados** (escritores TDD)
     não está verificado — no 1º ciclo light com ponytail ativo, observar e **registrar como item
     em `## Pontas soltas / follow-ups` da PR (Fase 7)**, que o close-out transcreve p/ issues.md.
2. **`SKILL.md`** — bullet da Fase 0 ganha "+ ponytail por tier (opcional)"; seção **Verification**
   da Fase 0 ganha sub-linha: "se ponytail presente e tier=light: nível confirmado com output".
3. **`tests/test_references.sh`** — 1 assert novo: `setup-gate.md` menciona `ponytail` (trava contra
   remoção acidental; consistente com o padrão grep raso do arquivo). `model-tiers.md` fica fora.
4. **CHANGELOG** — `[Unreleased]` → `### Added`, mesmo commit.

## Fora de escopo

- Instalar/configurar o ponytail (ação do usuário; o passo é condicional à presença).
- Injetar o ladder do ponytail nos prompts de despacho dos writers (seria replicar o plugin;
  só reavaliar depois do resultado do trial — ver nota do passo 7).
- Qualquer mudança em hooks/ ou no comportamento de enforcement.

## Critérios de aceite

1. `sh plugins/oli-dev/tests/run_all.sh` → ALL GREEN (incluindo o assert novo).
2. O texto do passo 7 não deixa ambiguidade nos 3 ramos (light+presente / full / ausente), com
   critério de detecção e de evidência operacionais (não subjetivos).
3. Invariantes preservados: tokens `main` (setup-gate.md) e asserts existentes intactos.
   `model-tiers.md`: o princípio/tabela do tier NÃO incorpora o ponytail; permitida apenas uma
   nota de cross-ref explicitamente rotulada "fora do escopo modelo" (ajuste adjudicado no review
   pós-código — achado L2: sem a nota, o doc "fonte única" induzia leitura incompleta do tier).
4. CHANGELOG no mesmo commit.
