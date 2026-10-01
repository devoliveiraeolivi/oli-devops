# Gates de qualidade

Cada gate tem um gatilho observável. Gatilho presente, gate obrigatório. Gate não executado entra no handoff com o motivo.

## Gate 0 — Decisão registrada

Gatilho: houve discussão de desenho, arquitetura ou alternativas.

1. Grave na spec (onde a regra de docs do repo mandar) uma lista numerada: o que foi decidido, o que fica fora e o tamanho previsto (componentes e arquivos de produção).
2. O usuário confirma esse texto antes de qualquer código. Sem confirmação, não há implementação. Registre o commit da versão confirmada: ele é a referência do Gate 3.
3. A implementação começa numa sessão nova, a partir da lista, e não do contexto compactado da discussão.
4. Mudar uma decisão, no código ou na spec, exige parar e pedir aprovação: o quê, por quê, custo. Com o sim, atualize a lista e registre o novo commit. Nunca reescreva a spec para justificar o que foi construído.

Por quê: no oli-indexador#232, a decisão (coordenador único, journal, sem síntese) ficou só no chat. Depois de 19 compactações, o agente implementou outra arquitetura (segmentos, síntese, reconciliação) e reescreveu a spec 0005 dentro do próprio PR para descrevê-la.

## Gate 1 — Premissas conferidas

Gatilho: a mudança ou a spec depende de afirmação sobre o estado atual (código, schema, dados, configuração, comportamento em produção).

1. Liste cada premissa em uma linha: afirmação + evidência (`arquivo:linha`, ou consulta e resultado).
2. Entregue só a lista a um agente em contexto novo, sem sua conclusão. Ele marca cada premissa como `confirmada`, `derrubada` ou `sem evidência`, citando `arquivo:linha`.
   - Claude: subagente (Explore para leitura ampla).
   - Codex: subagente ou sessão nova.
3. Premissa derrubada ou sem evidência volta para a spec antes do código. Se isso mudar uma decisão já confirmada (Gate 0), o usuário aprova de novo.

Por quê: conferir a spec 0005 do oli-indexador contra o código achou 6 premissas erradas. É o gate que mais rende.

## Gate 2 — Invariantes viram testes que falham

Gatilho: a mudança altera comportamento (não só docs ou configuração sem efeito).

1. Cada invariante ou critério de aceite da spec vira ao menos um teste.
2. Rode e veja falhar pelo motivo certo antes de implementar.
3. Inclua casos adversariais: limite, vazio ou nulo, duplicado, ordem, repetição e idempotência, entrada malformada, estado legado.
4. Os testes nascem da spec, não da implementação. Quem escreve os testes que definem o comportamento é o contexto principal; se outro agente escrever, um agente em contexto novo os revisa contra a spec antes do código.

Por quê: escritores de teste delegados sem revisão produziram testes que espelhavam as suposições de quem implementou.

## Gate 3 — Conformidade, depois bugs, em contexto novo

Gatilho: há diff para PR.

1. Conformidade primeiro. Um agente em contexto novo recebe a lista aprovada, lida do commit registrado no Gate 0 (`git show <sha>:<spec>`, nunca da branch do PR), e o diff, e responde: implementa exatamente a lista? O que sobra? O que falta? Componente, fase ou abstração fora da lista, ou mudança na lista ou na spec sem aprovação do usuário, é bloqueio. O que falta entra no handoff.
2. Depois, bugs:
   - Claude: `/code-review` em nível high (medium se o diff for só docs).
   - Segundo par, o outro agente: numa sessão Claude, `codex review --base origin/main`; numa sessão Codex, `/code-review` high numa sessão Claude.
3. Confirme cada achado no código antes de aceitar ou rejeitar. Registre os rejeitados com o motivo.

Por quê: no #232, a revisão de bug achou vários P1 dentro da arquitetura errada, e nenhuma perguntou se ela era a combinada.

## Disjuntor

Gatilho: segunda rodada de revisão (depois de corrigir a primeira) ainda com achado P0/P1, ou arquivos de produção alterados acima do dobro do previsto no Gate 0 (testes não contam).

Pare. Não siga consertando. Reporte ao usuário o que foi decidido, o que foi feito, onde divergiu e as opções. Rodadas seguidas de P1 costumam indicar desenho errado, não bug isolado.

Por quê: no #232, foram 6 P1 no primeiro review e mais 3 depois das correções, horas consolidando uma máquina que ninguém pediu.

## Gate 4 — Dado real antes de números

Gatilho: a entrega afirma número, contagem, custo, taxa ou estado de dados.

- Leia a fonte real em modo somente leitura (SQL read-only, API GET, arquivo, log). Cite a consulta e o resultado.
- Número derivado de código, fixture ou suposição é hipótese; rotule assim.
- Sem acesso somente leitura: declare a pendência. Não estime.

## Divisão de modelos

- Mudança acoplada (partes que precisam ficar coerentes entre si): contexto principal. No Claude, Opus 5.5.
- Busca ampla e tarefa mecânica independente (varredura, renomeação em lote, fixtures): subagente. No Claude, Sonnet 5.5.
- A conferência de premissas (Gate 1) e a revisão de testes e diff (Gates 2 e 3) nunca ficam com o agente que implementou.
