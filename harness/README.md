# harness/

Harness de engenharia compartilhado entre Claude Code e Codex: a skill
[`engineering-task-harness`](engineering-task-harness/SKILL.md) e seus hooks.

**Não faz parte do baseline de segurança deste repo.** Cadência própria:

- Sem tag e sem bump SemVer do baseline. Fora do `CHANGELOG.md` raiz. Histórico: `git log -- harness/`.
- CI próprio: [`.github/workflows/harness.yml`](../.github/workflows/harness.yml), só com mudança em
  `harness/**`. Falha aqui não trava release de segurança.
- Consumidores do baseline não são afetados: o Renovate acompanha tags.
- Commits com escopo `(harness)`, ex.: `feat(harness): ...`.

## Instalação (uma vez por máquina)

A skill é instalada por symlink a partir deste checkout, e os repos a referenciam por nome
(`$engineering-task-harness`), nunca por caminho. O checkout base do oli-devops fica na `main`:
numa branch sem `harness/`, os dois agentes perdem a skill e os hooks falham abertos.

```bash
H="$HOME/Documents/GitHub/oli-devops/harness/engineering-task-harness"
ln -s "$H" ~/.codex/skills/engineering-task-harness    # Codex
ln -s "$H" ~/.claude/skills/engineering-task-harness   # Claude Code
```

### Hooks

| Evento | Script | Papel |
|---|---|---|
| SessionStart | `scripts/session_context.py` | contexto Git + lembrete dos gates |
| PreToolUse (Bash) | `scripts/git_guard.py` | bloqueia remoção de worktree, exclusão forçada (`-D`) ou remota de branch e `rm -rf` em raiz de repo |
| PreToolUse (Bash) | `scripts/pre-push-gate.sh` | roda a verificação do repo no `git push` (na dúvida, libera; o CI valida o SHA) |
| PreToolUse (Bash) | `scripts/branch-state-guard.sh` | bloqueia commit/push de branch com PR mergeado |

Os dois hooks shell usam `scripts/git_targets.py` para achar o repo e os refs de cada
push/commit (`cd X && git push`, `git -C X push origin feat`), não o cwd do evento. Os scripts falam o protocolo comum
aos dois agentes: JSON `hookSpecificOutput` com exit 0, ou exit 2 com o motivo no stderr. Outro
exit code conta como falha do hook e o comando segue.

Os hooks não se registram sozinhos: copie o bloco do agente para o arquivo de configuração dele.
Troque `/Users/<você>` pelo seu home (os comandos usam caminho absoluto).

**Codex** (`~/.codex/hooks.json`). Mudar `command`, `matcher`, `timeout` ou `statusMessage` de
uma entrada exige confiar nela de novo em `/hooks`; mudar o script não.

```json
{
  "hooks": {
    "SessionStart": [
      {"matcher": "^(startup|resume|compact)$", "hooks": [
        {"type": "command", "command": "/usr/bin/python3 /Users/<você>/.codex/skills/engineering-task-harness/scripts/session_context.py", "timeout": 10}
      ]}
    ],
    "PreToolUse": [
      {"matcher": "^Bash$", "hooks": [
        {"type": "command", "command": "/usr/bin/python3 /Users/<você>/.codex/skills/engineering-task-harness/scripts/git_guard.py", "timeout": 5},
        {"type": "command", "command": "/bin/sh /Users/<você>/.codex/skills/engineering-task-harness/scripts/pre-push-gate.sh", "timeout": 600},
        {"type": "command", "command": "/bin/sh /Users/<você>/.codex/skills/engineering-task-harness/scripts/branch-state-guard.sh", "timeout": 30}
      ]}
    ]
  }
}
```

**Claude Code** (`~/.claude/settings.json`):

```json
{
  "hooks": {
    "SessionStart": [
      {"matcher": "startup|resume|compact", "hooks": [
        {"type": "command", "command": "python3 /Users/<você>/.claude/skills/engineering-task-harness/scripts/session_context.py", "timeout": 10}
      ]}
    ],
    "PreToolUse": [
      {"matcher": "Bash", "hooks": [
        {"type": "command", "command": "python3 /Users/<você>/.claude/skills/engineering-task-harness/scripts/git_guard.py", "timeout": 5},
        {"type": "command", "command": "sh /Users/<você>/.claude/skills/engineering-task-harness/scripts/pre-push-gate.sh", "timeout": 600},
        {"type": "command", "command": "sh /Users/<você>/.claude/skills/engineering-task-harness/scripts/branch-state-guard.sh", "timeout": 30}
      ]}
    ]
  }
}
```

## Atualização

`git -C ~/Documents/GitHub/oli-devops pull --ff-only` na `main`. A skill nova vale na próxima
sessão; os hooks, na próxima chamada.

## Testes

```bash
cd harness/engineering-task-harness
python3 -m unittest discover -s tests   # git_guard, task_harness, session_context
sh tests/run_all.sh                     # hooks shell (matriz sh + dash) + shellcheck
```

## Limites

- Scripts Python devem rodar em 3.9: o hook do Codex usa `/usr/bin/python3` (3.9 no macOS), e o
  `python3` do sandbox do Codex também é esse. O CI testa 3.9 e a versão atual.
- Codex na nuvem e Claude web não têm a skill: a instalação é local.
- `~/.codex/skills` está deprecado no Codex (a 0.144.6 ainda lê); o local atual é `~/.agents/skills`.
