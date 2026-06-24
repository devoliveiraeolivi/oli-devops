# Review gates (Producer-Reviewer, sempre Opus 4.8)

## Fase 2 — pré-código (sobre brainstorm + spec)
Despache **1 subagente `staff-reviewer` com `model: "opus"`** (effort alto). Mandato cético:
complexidade desnecessária, requisito ambíguo, escopo inflado, riscos não tratados, suposições
não verificadas. Incorpore achados, atualize o spec, checkpoint commit. Só avance quando o spec
sobrevive ao review.

## Fase 5 — pós-código (sobre o diff)
Encadeie, todos os subagentes em **Opus 4.8**. A ordem é proposital (não reordene):
1. `/code-review` (effort alto) — bugs de correção; verifique achados adversarialmente.
2. `/simplify` — reuso/simplificação/eficiência (qualidade, não bugs). Roda **depois** do code-review
   (não simplificar código com bug em aberto) e **antes** do verify (o verify valida o resultado já simplificado).
3. `verify` / `superpowers:verification-before-completion` — rode testes/app de verdade, com evidência.

### O `/simplify` NÃO é soberano
As mudanças do simplify são **propostas que precisam sobreviver a dois filtros** antes de ir pra PR:
- **Gate duro = `verify`.** Como o simplify aplica edições, ele pode introduzir regressão. O `verify`
  (passo 3) roda logo após e é quem decide: testes quebraram → a mudança do simplify **não passa**
  (reverter/corrigir). "Quality only, não caça bug" ≠ "não pode causar bug".
- **Julgamento do conductor** (filosofia `superpowers:receiving-code-review` — verificar, não concordar
  por performance). **Rejeite** mudanças do simplify que: piorem legibilidade ou troquem clareza
  intencional por concisão; violem convenções do projeto (português, naming, line 100, estrutura de
  arquivos); ou sejam *churn* cosmético sem ganho real.

Quem tem a palavra final no gate pós-código é o **`verify`** (objetivo: testes verdes com evidência)
somado ao conductor (subjetivo: melhora real + respeito às convenções). Nada vai pra push sem isso.

### Sub-gate condicional de security-review
Se o diff toca **superfície sensível** — auth, secrets/`.env`, SQL/RPC, rede/HTTP, credenciais,
browser/`page.evaluate` — dispare também `/security-review` (ou o plugin `security-guidance`).
Detecte pelos paths/conteúdo do diff. Não roda em todo ciclo.
