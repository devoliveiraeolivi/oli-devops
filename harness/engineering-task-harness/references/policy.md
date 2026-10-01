# Política de tasks e worktrees

## Princípio

Uma task deve ter um ambiente identificável, uma linhagem Git verificável e um encerramento explícito. Worktree é isolamento de checkout, não unidade de verdade nem prova de que o trabalho foi entregue.

## Escolha do ambiente

| Modo | Ambiente padrão | Exceção |
|---|---|---|
| `review` | checkout atual, somente leitura | worktree se for necessário instalar dependências ou executar artefatos incompatíveis |
| `spec` | checkout atual para descoberta; worktree dedicada para persistir | documento descartável sem commit pode permanecer fora do repo |
| `feature` | worktree dedicada do agente, baseada no branch aprovado | reutilizar somente uma worktree já dedicada à mesma task |
| `debug` | ambiente que reproduz o erro | a correção deve migrar para worktree dedicada se o reproducer for compartilhado ou estiver sujo |

Prefira a worktree gerenciada pelo agente: Codex em `$CODEX_HOME/worktrees`; Claude em `<repo>/.claude/worktrees` (`EnterWorktree`). Não crie clones ou worktrees irmãos no diretório de repositórios quando o agente já oferece isolamento por task.

## Início

1. Resolva o clone-base e o branch-base aprovados.
2. Inspecione `git status`, `git worktree list --porcelain`, branches relacionadas e PRs existentes.
3. Registre `HEAD` inicial e alterações locais.
4. Não copie mudanças sujas para outra worktree sem dizer exatamente o que está sendo transplantado.
5. Para implementação nova, use branch `<agente>/<slug>` (`codex/…` ou `claude/…`) quando criar uma branch persistente.

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
- `REVISAR_STATUS_DESCONHECIDO` / `REVISAR_GITHUB_INDISPONIVEL`: estado local ou remoto não verificado; nunca vira candidata.
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

Os mesmos scripts servem aos dois agentes: Codex em `~/.codex/hooks.json`, Claude em `~/.claude/settings.json` (instalação no README de `harness/`, repo oli-devops). Use `SessionStart` para adicionar o contexto Git e recordar o protocolo. Não crie nem remova worktrees nesse hook. `SessionEnd` não é um gatilho confiável de limpeza: pode ocorrer após ociosidade e não prova que PR, deploy ou aprovação foram concluídos.

Um `PreToolUse` global pode bloquear padrões destrutivos, mas deve ser pequeno e conservador. Não tente interpretar pipelines shell complexos por regex como se isso fosse uma política de segurança completa.

Os hooks rodam antes do comando e não preveem o efeito de comandos anteriores na mesma linha: os de push, na dúvida, liberam (o CI é a autoridade). O guardrail instalado bloqueia `git worktree remove/prune`, exclusão forçada de branch local (`-D`, `-d -f`; `-d` passa, porque o git só apaga branch mergeada), exclusão de branch remota (inclusive `push --prune`/`--mirror`) e `rm -rf` na raiz protegida, em ancestral dela ou em raiz de repo/worktree dentro dela (caminho relativo resolvido pelo cwd). Texto entre aspas conta como comando, salvo contextos de dado: mensagem ou corpo (`-m`, `--body`, `--title`), padrão de busca (`grep`, `rg`) e heredoc de `cat`/`tee`; em dado, só `$(...)` e crase contam. As regras diferenciam maiúsculas: "Git" em texto passa. Após autorização explícita dos alvos exatos, a exceção é local ao comando: `ENGINEERING_HARNESS_ALLOW_RAW_GIT_CLEANUP=1` como prefixo do próprio comando (em comentário ou mensagem não vale); não exporte essa variável para a sessão.
