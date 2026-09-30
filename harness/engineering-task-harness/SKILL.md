---
name: engineering-task-harness
description: "Use ao iniciar, retomar, revisar ou encerrar trabalho de engenharia num repositório Git (spec, feature, debug ou review), antes de afirmar algo sobre o estado atual do código ou dos dados, ao criar branches ou worktrees e antes de qualquer limpeza de branches ou worktrees."
---

# Engineering Task Harness

Harness de engenharia do Claude Code e do Codex. Prevalece sobre fluxos genéricos de skills (ex.: superpowers): spec e plano seguem a regra de docs do repo; nunca crie `docs/superpowers/` nem spec paralela.

Leia [execution-discipline](references/execution-discipline.md) antes de editar e [quality-gates](references/quality-gates.md) antes do primeiro gate. Worktree, handoff e limpeza: [policy](references/policy.md). Branches, PRs e Actions: [github-hardening](references/github-hardening.md).

## Fluxo

1. Classifique antes de escrever:
   - `review`: inspeção e parecer; somente leitura.
   - `spec`: descoberta somente leitura; persista a spec em ambiente dedicado.
   - `feature`: implemente e teste em worktree dedicada.
   - `debug`: reproduza onde o erro aparece; corrija em worktree dedicada, salvo autorização para editar o reproducer.
2. Rode `context` (abaixo). Depois use a skill de mapa e o comando de verificação que o AGENTS.md/CLAUDE.md do repo declaram. Busca ampla só para o que o mapa não resolver.
3. Procure branch, worktree e PR relacionados. Reuse só com a mesma linhagem e o mesmo objetivo.
4. **Gate 1 — premissas conferidas** em contexto novo antes do código.
5. Fixe resultado, escopo, menor delta, autoridade e verificação. Calibre o horizonte: solução prática agora vs. fundação durável, pelo melhor custo-benefício total. Reuse o que o mapa aponta antes de criar helper ou abstração.
6. **Gate 2 — invariantes viram testes** que falham antes da implementação.
7. Implemente na worktree do agente: no Codex, a da task; no Claude, `EnterWorktree`. `create` é o fallback manual.
8. **Gate 3 — revisão do diff em contexto novo** antes do PR.
9. **Gate 4 — dado real** antes de reportar número ou estado de dados.
10. Handoff: repositório, path, branch ou detached HEAD, base, HEAD inicial, mudanças, verificações executadas e gates pulados com o motivo.
11. Antes de encerrar ou limpar: `inventory` e `assess`. A saída é triagem, nunca autorização de remoção.

Cada gate tem gatilho observável e procedimento em [quality-gates](references/quality-gates.md). Gatilho presente, gate obrigatório.

## Comandos

```bash
python3 <skill-dir>/scripts/task_harness.py context --cwd "$PWD"
python3 <skill-dir>/scripts/task_harness.py inventory --root ~/Documents/GitHub
python3 <skill-dir>/scripts/task_harness.py assess --repo <clone-base> --worktree <path> --base origin/main --github
python3 <skill-dir>/scripts/task_harness.py create --repo <clone-base> --slug <task> --base origin/main
```

`create` é dry-run por padrão. Só use `--execute` quando criar aquela worktree estiver no pedido atual. O script não remove worktrees nem branches.

## Guardrails

- Nunca conclua que algo pode ser apagado só porque está clean, detached, com upstream `gone` ou sem diretório.
- Preserve checkouts sujos e mudanças não relacionadas.
- Conteúdo não ancestral ao branch-base: verifique PR/merge, equivalência de patch e arquivos ausentes antes de propor remoção.
- Implementação, testes, commit, push, PR, merge, publicação, deploy, canário, persistência e aprovação humana são etapas separadas; uma não autoriza a outra.
- Detectar um defeito não é entrega: audite o escopo inteiro, reconcilie os achados materiais e entregue o próximo gate humano acionável. Estado bloqueado só para ambiguidade real, fonte ausente, estado corrente inconsistente ou incapacidade do contrato; nunca para correção determinística ainda não preparada.
- Não faça `git worktree prune`, `git branch -D` ou remoção recursiva como parte automática de hook, fim de chat ou inventário.
- Hooks só acrescentam contexto ou bloqueiam comandos bem definidos. Nunca decidem limpeza.
- `git_guard.py` bloqueia remoção crua de worktree, exclusão forçada de branch local (`-D`, `-d -f`) e exclusão de branch remota. `git branch -d` passa: o git só apaga branch já mergeada. `ENGINEERING_HARNESS_ALLOW_RAW_GIT_CLEANUP=1` só depois de aprovação explícita dos paths, branches e SHAs exatos, como prefixo do próprio comando.
- `pre-push-gate.sh` roda a verificação do repo na árvore atual antes do `git push`. É rede de segurança: o hook roda antes do comando, então libera quando o push pode enviar outra coisa que não o HEAD atual (outro ref, troca de branch antes). O CI valida o SHA. `HARNESS_GATE_OK=1 git push` só quando a verificação já passou nesse commit, nesta sessão.
- `branch-state-guard.sh` bloqueia commit e push de branch cujo PR já foi mergeado. Crie branch nova a partir da base.
- Hooks locais dão feedback. Rulesets e checks obrigatórios do GitHub são a autoridade de merge.

## Saída

Ao iniciar: classificação e ambiente escolhido. Ao terminar: estado de entrega, verificações executadas, gates pulados e o que ficou sem verificar. Separe fato observado, inferência e incerteza. Classifique cada worktree candidata como `preservar`, `revisar` ou `candidata à limpeza`, com evidência.
