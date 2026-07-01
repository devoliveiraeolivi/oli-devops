# oli-dev

Maestro do ciclo de desenvolvimento OLI. Um plugin fino que **conduz** as fases do ciclo
encadeando skills do **superpowers** com gates opinativos.

## Requisitos
- **superpowers** instalado (este plugin invoca suas skills). Sem ele, a skill avisa e para.
- **Loop principal em Opus 4.8.** Uma skill é markdown e não troca o modelo da sessão; a Fase 0
  verifica e bloqueia até você confirmar. O conductor é sempre Opus; os subagentes despachados
  (escritores TDD + staff-reviewer) seguem o **tier** (`full`=Opus, `light`=Sonnet).

## Instalação
```
/plugin marketplace add devoliveiraeolivi/oli-devops
/plugin install oli-dev
```

## Uso
- `/oli-dev <ideia da feature>` → ciclo completo (Fases 0–7), termina em PR aberta. Tier `full` (default).
- `/oli-dev light <ideia>` → tier `light`: escritores TDD + staff-reviewer em **Sonnet 4.6** (custo/latência;
  conductor e `/code-review`/`verify`/`/security-review` inalterados). Ver `skills/dev-cycle/references/model-tiers.md`.
- `/oli-dev finalize` → close-out + limpeza pós-merge (Fase 8), depois que a PR foi mergeada.

## O que ele faz
worktree da main → brainstorm → review staff cético → plano → escrita TDD por subagente
(modelo por tier) → code-review/simplify/verify (+security-review condicional) → pre-push gate → PR → finalize.

## Gates duros (invioláveis)
1. Uma branch por ciclo, da `main`, sem stacked. 2. Worktree sempre, da `main`.
3. Nunca deletar branch sem `gh pr view --json state == MERGED`. 4. Conductor sempre Opus; subagentes despachados seguem o tier.

## Hook de pre-push
`hooks/pre-push-gate.sh` é um backstop PreToolUse: em `git push`, detecta a stack
(`pyproject.toml`→python, `package.json`→node) e bloqueia (exit 2) se lint/test/typecheck falhar.
Stack desconhecida ou ferramenta ausente não bloqueia.

## Testes do plugin
`sh plugins/oli-dev/tests/run_all.sh` → `ALL GREEN`.
