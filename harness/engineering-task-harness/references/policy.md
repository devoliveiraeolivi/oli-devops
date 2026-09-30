# Política de tasks e worktrees

## Princípio

Uma task deve ter um ambiente identificável, uma linhagem Git verificável e um encerramento explícito. Worktree é isolamento de checkout, não unidade de verdade nem prova de que o trabalho foi entregue.

## Escolha do ambiente

| Modo | Ambiente padrão | Exceção |
|---|---|---|
| `review` | checkout atual, somente leitura | worktree se for necessário instalar dependências ou executar artefatos incompatíveis |
| `spec` | checkout atual para descoberta; worktree dedicada para persistir | documento descartável sem commit pode permanecer fora do repo |
| `feature` | worktree Codex dedicada baseada no branch aprovado | reutilizar somente uma worktree já dedicada à mesma task |
| `debug` | ambiente que reproduz o erro | a correção deve migrar para worktree dedicada se o reproducer for compartilhado ou estiver sujo |

Prefira worktrees gerenciadas pelo Codex em `$CODEX_HOME/worktrees`. Não crie clones ou worktrees irmãos no diretório visual de repositórios quando o app já oferece isolamento por task.

## Início

1. Resolva o clone-base e o branch-base aprovados.
2. Inspecione `git status`, `git worktree list --porcelain`, branches relacionadas e PRs existentes.
3. Registre `HEAD` inicial e alterações locais.
4. Não copie mudanças sujas para outra worktree sem dizer exatamente o que está sendo transplantado.
5. Para implementação nova, use branch `codex/<slug>` quando criar uma branch persistente.

## Durante

- Uma task por worktree; uma branch mutável não pode pertencer a duas worktrees.
- Não use o clone-base como depósito de experimentos concorrentes.
- Dependências, caches e servidores locais pertencem ao ambiente que efetivamente os executa.
- Em debug visual, confirme o `cwd` do processo/porta antes de atribuir o resultado a uma worktree.
- Faça checkpoints Git pequenos quando isso proteger trabalho, sem confundir commit com entrega.

## Encerramento

Classifique cada ambiente:

- `PRESERVAR_DIRTY`: há alterações tracked ou untracked.
- `PRESERVAR_ATIVO`: chat, processo, preview ou investigação ainda depende do path.
- `REVISAR_DETACHED`: HEAD detached exige confirmar snapshot, branch ou equivalência.
- `REVISAR_NAO_MERGEADO`: HEAD não é ancestral do branch-base.
- `REVISAR_PR`: PR aberto/fechado sem merge ou estado remoto desconhecido.
- `CANDIDATA_MERGEADA`: clean e HEAD ancestral do branch-base; ainda requer aprovação de limpeza.
- `METADADO_PODAVEL`: diretório ausente e registro Git prunable; primeiro registre o HEAD e audite a branch.

Antes de remover conteúdo não ancestral:

1. registre path, branch e SHA;
2. confira PRs e branches remotas;
3. use `git cherry` e, quando houve squash/rebase, `git range-diff`;
4. compare a lista de arquivos com o branch-base;
5. preserve uma ref ou bundle recuperável se ainda houver dúvida;
6. apresente a lista exata ao usuário antes de executar.

Use `assess --github` antes da decisão final. Um PR `MERGED` sem ancestralidade local normalmente indica squash ou rebase; ele exige revisão de equivalência, não remoção automática. PR aberto sempre preserva a worktree.

## Hooks

Use `SessionStart` para adicionar o contexto Git e recordar o protocolo. Não crie nem remova worktrees nesse hook. `SessionEnd` não é um gatilho confiável de limpeza: pode ocorrer após ociosidade e não prova que PR, deploy ou aprovação foram concluídos.

Um `PreToolUse` global pode bloquear padrões destrutivos, mas deve ser pequeno e conservador. Não tente interpretar pipelines shell complexos por regex como se isso fosse uma política de segurança completa.

O guardrail instalado bloqueia `git worktree remove/prune`, exclusão local/remota de branch e `rm -rf` em raízes conhecidas. Após autorização explícita dos alvos exatos, a exceção é local ao comando com `ENGINEERING_HARNESS_ALLOW_RAW_GIT_CLEANUP=1`; não exporte essa variável para a sessão.
