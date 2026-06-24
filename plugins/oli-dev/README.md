# oli-dev

Maestro do ciclo de desenvolvimento OLI. Um plugin fino que **conduz** as fases do ciclo
encadeando skills do **superpowers** com gates opinativos.

## Requisitos
- **superpowers** instalado (este plugin invoca suas skills). Sem ele, a skill avisa e para.
- **Loop principal em Opus 4.8.** Uma skill é markdown e não troca o modelo da sessão; a Fase 0
  verifica e bloqueia até você confirmar. Os subagentes de review/escrita já rodam em Opus.

## Instalação
```
/plugin marketplace add devoliveiraeolivi/oli-devops
/plugin install oli-dev
```

## Uso
- `/oli-dev <ideia da feature>` → ciclo completo (Fases 0–7), termina em PR aberta.
- `/oli-dev finalize` → close-out + limpeza pós-merge (Fase 8), depois que a PR foi mergeada.

## O que ele faz
worktree da main → brainstorm → review staff cético (Opus) → plano → escrita TDD por subagente
Opus → code-review/simplify/verify (+security-review condicional) → pre-push gate → PR → finalize.

## Gates duros (invioláveis)
1. Uma branch por ciclo, da `main`, sem stacked. 2. Worktree sempre, da `main`.
3. Nunca deletar branch sem `gh pr view --json state == MERGED`. 4. Todo review em Opus 4.8.

## Hook de pre-push
`hooks/pre-push-gate.sh` é um backstop PreToolUse: em `git push`, detecta a stack
(`pyproject.toml`→python, `package.json`→node) e bloqueia (exit 2) se lint/test/typecheck falhar.
Stack desconhecida ou ferramenta ausente não bloqueia.

## Testes do plugin
`sh plugins/oli-dev/tests/run_all.sh` → `ALL GREEN`.
