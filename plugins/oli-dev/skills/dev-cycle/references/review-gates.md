# Review gates (Producer-Reviewer, sempre Opus 4.8)

## Fase 2 — pré-código (sobre brainstorm + spec)
Despache **1 subagente `staff-reviewer` com `model: "opus"`** (effort alto). Mandato cético:
complexidade desnecessária, requisito ambíguo, escopo inflado, riscos não tratados, suposições
não verificadas. Incorpore achados, atualize o spec, checkpoint commit. Só avance quando o spec
sobrevive ao review.

## Fase 5 — pós-código (sobre o diff)
Encadeie, todos os subagentes em **Opus 4.8**:
1. `/code-review` (effort alto) — bugs de correção; verifique achados adversarialmente.
2. `/simplify` — reuso/simplificação/eficiência (qualidade, não bugs).
3. `verify` / `superpowers:verification-before-completion` — rode testes/app de verdade, com evidência.

### Sub-gate condicional de security-review
Se o diff toca **superfície sensível** — auth, secrets/`.env`, SQL/RPC, rede/HTTP, credenciais,
browser/`page.evaluate` — dispare também `/security-review` (ou o plugin `security-guidance`).
Detecte pelos paths/conteúdo do diff. Não roda em todo ciclo.
