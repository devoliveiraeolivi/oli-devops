---
name: engineering-task-harness
description: "Organiza o ciclo de tasks de engenharia em repositórios Git: classifica trabalho de spec, revisão, feature ou debug; controla escopo, evidência, validação e gates; escolhe entre checkout local e worktree isolada; audita estado, origem, mudanças e encerramento; e prepara limpeza segura sem apagar trabalho automaticamente. Use ao iniciar, retomar, revisar ou encerrar desenvolvimento, ao criar worktrees/branches, quando houver muitos checkouts concorrentes, ou antes de qualquer limpeza de branches e worktrees."
---

# Engineering Task Harness

Use este harness para tornar o ambiente e a execução de cada task explícitos e auditáveis. Leia [references/execution-discipline.md](references/execution-discipline.md) antes de editar e ao concluir. Leia [references/policy.md](references/policy.md) quando precisar decidir criação, reutilização, handoff ou limpeza de worktree. Para proteção de branches, PRs e Actions, leia [references/github-hardening.md](references/github-hardening.md).

## Fluxo obrigatório

1. Classifique a intenção antes de escrever:
   - `review`: inspeção e parecer; permaneça somente leitura.
   - `spec`: descoberta pode ser local e somente leitura; persista a spec em ambiente dedicado.
   - `feature`: implemente e teste em worktree dedicada.
   - `debug`: reproduza no ambiente que manifesta o erro; implemente a correção em worktree dedicada, salvo autorização explícita para editar o reproducer.
2. Inspecione o contexto com `scripts/task_harness.py context --cwd <path>`.
3. Antes de criar trabalho, procure branch, worktree e PR relacionados. Reuse somente quando a linhagem e o objetivo coincidirem.
4. Antes de editar, fixe resultado, escopo, evidência atual, menor delta, autoridade e verificação relevante. Calibre também o horizonte da solução conforme `references/execution-discipline.md`: compare a resposta prática para agora com eventual fundação durável e escolha pelo melhor custo-benefício total, não pela menor implementação isoladamente.
5. Use preferencialmente a worktree gerenciada pelo Codex já associada à task. Crie uma manual apenas quando o app não puder preparar o ambiente necessário.
6. Registre no handoff: repositório, path, branch ou detached HEAD, base, HEAD inicial, mudanças, verificações e gates ainda não executados.
7. Antes de encerrar ou limpar, execute `inventory` e `assess`. Trate a saída como triagem, nunca como autorização de remoção.

## Comandos

```bash
python3 <skill-dir>/scripts/task_harness.py context --cwd "$PWD"
python3 <skill-dir>/scripts/task_harness.py inventory --root ~/Documents/GitHub
python3 <skill-dir>/scripts/task_harness.py assess --repo <clone-base> --worktree <path> --base origin/main --github
python3 <skill-dir>/scripts/task_harness.py create --repo <clone-base> --slug <task> --base origin/main
```

`create` é dry-run por padrão. Só use `--execute` quando a criação daquela worktree estiver dentro do pedido atual. O script não remove worktrees nem branches.

## Guardrails

- Nunca conclua que algo pode ser apagado apenas porque está clean, detached, com upstream `gone` ou sem diretório.
- Preserve checkouts sujos e mudanças não relacionadas.
- Para conteúdo não ancestral ao branch-base, verifique PR/merge, equivalência de patch e arquivos ausentes antes de propor remoção.
- Não faça `git worktree prune`, `git branch -D` ou remoção recursiva como parte automática de hook, fim de chat ou inventário.
- Mantenha separados: implementação, testes, commit, push, PR, merge, publicação, deploy, canário, persistência e aprovação humana.
- Quando o produto define um resultado operacional (por exemplo, pré-aprovação),
  detectar um defeito é etapa intermediária, não handoff final. Audite o escopo
  inteiro, reconcilie todos os findings materiais e entregue o próximo gate humano
  acionável. Use estado bloqueado apenas para ambiguidade real, ausência de fonte,
  inconsistência do estado corrente ou incapacidade do contrato; não para correção
  determinística ainda não preparada.
- Hooks apenas acrescentam contexto ou bloqueiam comandos perigosos bem definidos; nunca tomam decisões semânticas de limpeza.
- O guardrail bloqueia comandos crus de remoção de worktree/branch. Só use `ENGINEERING_HARNESS_ALLOW_RAW_GIT_CLEANUP=1` após aprovação explícita dos paths, branches e SHAs exatos.
- Git hooks locais melhoram feedback, mas GitHub rulesets e checks obrigatórios são a autoridade de merge.

## Saída esperada

Ao iniciar, informe a classificação e o ambiente escolhido. Ao terminar, informe o estado de entrega, as verificações executadas e o que permaneceu não verificado. Em análises complexas, diferencie fato observado, inferência e incerteza material. Classifique cada worktree candidata como `preservar`, `revisar` ou `candidata à limpeza`, com evidência.
