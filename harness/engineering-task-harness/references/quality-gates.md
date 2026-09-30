# Gates de qualidade

Cada gate tem um gatilho observável. Gatilho presente, gate obrigatório. Gate não executado entra no handoff com o motivo.

## Gate 1 — Premissas conferidas

Gatilho: a mudança ou a spec depende de afirmação sobre o estado atual (código, schema, dados, configuração, comportamento em produção).

1. Liste cada premissa em uma linha: afirmação + evidência (`arquivo:linha`, ou consulta e resultado).
2. Entregue só a lista a um agente em contexto novo, sem sua conclusão. Ele marca cada premissa como `confirmada`, `derrubada` ou `sem evidência`, citando `arquivo:linha`.
   - Claude: subagente (Explore para leitura ampla).
   - Codex: subagente ou sessão nova.
3. Premissa derrubada ou sem evidência volta para a spec antes do código.

Por quê: conferir a spec 0005 do oli-indexador contra o código achou 6 premissas erradas. É o gate que mais rende.

## Gate 2 — Invariantes viram testes que falham

Gatilho: a mudança altera comportamento (não só docs ou configuração sem efeito).

1. Cada invariante ou critério de aceite da spec vira ao menos um teste.
2. Rode e veja falhar pelo motivo certo antes de implementar.
3. Inclua casos adversariais: limite, vazio ou nulo, duplicado, ordem, repetição e idempotência, entrada malformada, estado legado.
4. Os testes nascem da spec, não da implementação. Quem escreve os testes que definem o comportamento é o contexto principal; se outro agente escrever, um agente em contexto novo os revisa contra a spec antes do código.

Por quê: escritores de teste delegados sem revisão produziram testes que espelhavam as suposições de quem implementou.

## Gate 3 — Revisão do diff em contexto novo

Gatilho: há diff para PR.

- Claude: `/code-review` em nível high (medium se o diff for só docs).
- Segundo par, o outro agente:
  - numa sessão Claude, rode `codex review --base origin/main`;
  - numa sessão Codex, peça `/code-review` high numa sessão Claude.
- Confirme cada achado no código antes de aceitar ou rejeitar. Registre os rejeitados com o motivo.

## Gate 4 — Dado real antes de números

Gatilho: a entrega afirma número, contagem, custo, taxa ou estado de dados.

- Leia a fonte real em modo somente leitura (SQL read-only, API GET, arquivo, log). Cite a consulta e o resultado.
- Número derivado de código, fixture ou suposição é hipótese; rotule assim.
- Sem acesso somente leitura: declare a pendência. Não estime.

## Divisão de modelos

- Mudança acoplada (partes que precisam ficar coerentes entre si): contexto principal. No Claude, Opus 5.5.
- Busca ampla e tarefa mecânica independente (varredura, renomeação em lote, fixtures): subagente. No Claude, Sonnet 5.5.
- A conferência de premissas (Gate 1) e a revisão de testes e diff (Gates 2 e 3) nunca ficam com o agente que implementou.
