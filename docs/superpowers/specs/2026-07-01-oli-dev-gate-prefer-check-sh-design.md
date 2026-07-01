# Design — pre-push gate do oli-dev prefere `scripts/check.sh`

**Data:** 2026-07-01
**Repo:** oli-devops (plugin `oli-dev`)
**Status:** aprovado (brainstorm), pronto p/ plano

## Problema

O pre-push gate do oli-dev (Fase 6 + o hook backstop `hooks/pre-push-gate.sh`)
hardcoda, para Python: `black --check` · `ruff check` · `pytest` · `mypy src/`.
Isso **diverge do CI real** dos repos da frota e tem um bug de correção:

1. **`black` é legado.** A frota migrou para `ruff format`. Rodar `black --check`
   é redundante e pode conflitar com `ruff format --check`.
2. **`mypy` cru causa falso-bloqueio.** Repos como o oli-indexer rodam mypy
   **baseline-gated** (`mypy-baseline filter` — só falha em erro *novo*). O gate
   roda `mypy src/` cru → falha em erro de baseline que o CI **aprova**. Ou seja,
   o gate pode **bloquear um push que o CI passaria**.
3. **Redundância com o gate local do repo.** O oli-indexer (#356) introduziu
   `scripts/check.sh` (espelho exato do `ci.yml`, fonte única) + `.githooks/pre-push`
   que roda `check.sh --fast`. O push da Fase 7 leva `OLI_DEV_GATE_OK=1` (pula o
   hook do oli-dev), mas o git-hook do repo ainda roda `check.sh --fast` → ruff+mypy
   rodam duas vezes, de formas diferentes.

Contexto que reforça: a **Fase 5** já roda `verify` (testes de verdade). Então
`pytest` na Fase 6 é parcialmente redundante *dentro do ciclo*.

## Objetivo

Fazer o gate **preferir o `scripts/check.sh` do repo** quando existe (fonte única
espelhando o CI), caindo para um fallback enxuto só na ausência. Isso mata a
divergência, o falso-bloqueio e a redundância de uma vez, e degrada de forma limpa
conforme mais repos adotam `check.sh`.

**Fora de escopo (proposta sinalizada, não implementar agora):** promover
`check.sh` + `.githooks/pre-push` a template do oli-devops. Node fallback fica
intacto (os problemas eram só do Python).

## Decisões (fechadas no brainstorm)

- **check.sh presente → roda `check.sh --fast`** (só ruff+mypy; testes já rodaram
  no `verify` da Fase 5). Igual ao que o `.githooks/pre-push` do repo chama.
- **Fallback (sem check.sh) → lint+type apenas:** `ruff check` + `ruff format --check`
  + `mypy`. Sai `black` e `pytest`.
- **mypy do fallback é baseline-aware:** se `.mypy-baseline.txt` existe e
  `mypy-baseline` está disponível, roda `mypy | mypy-baseline filter`; senão `mypy` cru.
- **Abordagem A (precedência em camadas):** check.sh no topo, antes do split
  python/node; fallback só na ausência. (Rejeitadas: B só-doc — meio-conserto; C
  hook fino que delega tudo — prematuro, perde proteção dos repos sem check.sh.)

## Design

### Componente 1 — precedência em `hooks/pre-push-gate.sh`

Depois das checagens existentes (é `git push`? tem marcador `OLI_DEV_GATE_OK`?
resolve `$dir` a partir do cwd do evento), a nova ordem de decisão:

```
1. Override de teste/escape: OLI_DEV_PYTHON_CMDS ou OLI_DEV_NODE_CMDS setado
   → honrado no seu branch de stack (mantém testes determinísticos + escape hatch).
2. senão, [ -x "$dir/scripts/check.sh" ]  → run "$dir/scripts/check.sh --fast"
      exit≠0 → bloqueia (exit 2); exit 0 → libera. (stack-agnóstico)
3. senão, [ -f "$dir/pyproject.toml" ]     → fallback python (Componente 2)
4. senão, [ -f "$dir/package.json" ]        → fallback node (inalterado)
5. senão                                     → stack desconhecida, libera (exit 0)
```

Guard concreto da camada 2 (pula check.sh se há override explícito, preservando
os testes atuais e o escape hatch):

```sh
if [ -z "${OLI_DEV_PYTHON_CMDS:-}${OLI_DEV_NODE_CMDS:-}" ] && [ -x "$dir/scripts/check.sh" ]; then
  cd "$dir" || exit 0
  if ! run "scripts/check.sh --fast"; then
    echo "BLOQUEADO: scripts/check.sh --fast falhou em $dir. Corrija antes do push." >&2
    exit 2
  fi
  exit 0
fi
```

Regras de degradação inalteradas (`uv`/`npm` ausente → avisa e libera, não bloqueia
por ausência de ferramenta).

### Componente 2 — fallback python enxuto + baseline-aware

O bloco `if [ -f "$dir/pyproject.toml" ]` passa a compor o comando default assim
(quando `OLI_DEV_PYTHON_CMDS` não está setado):

- Base: `uv run ruff check src/ && uv run ruff format --check src/ tests/`
- mypy:
  - se `[ -f "$dir/.mypy-baseline.txt" ]` **e** `mypy-baseline` resolve (via
    `uv run mypy-baseline --help` ou `command -v`):
    `uv run mypy src/ | uv run mypy-baseline filter --baseline-path .mypy-baseline.txt --allow-unsynced`
  - senão: `uv run mypy src/`
- Sem `black`. Sem `pytest`.

`OLI_DEV_PYTHON_CMDS`, quando setado, sobrescreve o conjunto inteiro (como hoje).
Degradação por `uv` ausente inalterada.

### Componente 3 — docs

- `skills/dev-cycle/references/pre-push-gate.md`: reescreve o bullet Python para a
  precedência nova (check.sh → fallback enxuto baseline-aware). Explica a remoção
  de `black` (legado) e de `pytest` (já roda no `verify` da Fase 5). Node inalterado.
- `skills/dev-cycle/SKILL.md` (Fase 6, linha ~46): `"black+ruff+pytest+mypy (ou
  lint+test+build)"` → `"scripts/check.sh --fast, ou ruff+mypy no fallback (ou
  lint+test+build p/ node)"`.

### Componente 4 — testes (`tests/test_pre_push_gate.sh`)

Casos novos (além dos existentes, que seguem verdes):

- **check.sh preferido:** repo temp com `scripts/check.sh` executável que emite um
  marcador e sai 0 → gate libera e o marcador aparece (rodou check.sh). Variante
  com `check.sh` saindo 1 → gate bloqueia (exit 2).
- **override vence check.sh:** com `OLI_DEV_PYTHON_CMDS` setado + `check.sh` presente
  → roda o override, não o check.sh.
- **sem black:** no fallback (sem check.sh), o comando composto não contém `black`.
- **mypy baseline-aware:** repo com `.mypy-baseline.txt` → o comando de mypy inclui
  `mypy-baseline filter`; sem o arquivo → mypy cru.

Suíte inteira (`tests/run_all.sh`) tem de passar — é pré-requisito de tag (golden
rule do CLAUDE.md). CHANGELOG atualizado no mesmo commit da mudança.

## Riscos / notas

- **Escape hatch preservado:** `OLI_DEV_*_CMDS` continua vencendo, então testes e
  casos especiais não quebram.
- **check.sh de outra stack:** o prefixo é stack-agnóstico de propósito — um repo
  node com `scripts/check.sh` também passa a preferi-lo. Aceitável (é a fonte única
  do repo).
- **Fallback continua best-effort:** para repos sem check.sh, o gate não conhece o
  CI exato; o baseline-aware cobre o caso conhecido (mypy), o resto fica pro CI no PR.
- **Convergência:** quando `check.sh` virar baseline da frota (follow-up sinalizado),
  o fallback vira caminho morto e o hook pode encolher pro modelo C.
