# Design — `branch-state-guard` (oli-dev, issue #6)

**Data:** 2026-06-24
**Issue:** [#6](https://github.com/devoliveiraeolivi/oli-devops/issues/6) — guard determinístico anti-órfão + reforço de worktree
**Repo:** oli-devops · plugin `plugins/oli-dev/`

## Problema

Duas falhas de processo recorrentes que o `dev-cycle` hoje só previne por orientação no
markdown (que o agente esquece sob pressão), não de forma determinística:

1. **Push/commit em branch já mergeada → commits órfãos.** Aconteceu na PR #4: após o
   squash merge, mais commits foram empurrados pra mesma branch e ficaram fora da `main`
   (recuperados via cherry-pick na PR #5). A regra existente ("nunca deletar branch sem
   `gh pr view --json state`") cobre o *delete*, mas não o **continuar trabalhando/empurrando**
   numa branch já mergeada.
2. **Trabalhar sem worktree**, direto numa feature branch no dir principal do repo — risco de
   sobrescrita entre sessões paralelas.

## Solução

Um hook determinístico **`branch-state-guard.sh`**, irmão do `pre-push-gate.sh`, registrado
como segundo hook PreToolUse/`Bash`. Mais um reforço de orientação na Fase 0 (SETUP gate).

### Princípios herdados do `pre-push-gate.sh`

- Lê o evento PreToolUse como JSON no **stdin**; parse via `python` (sem `jq`).
- Strip quote-aware de env-prefixes `VAR=val ` antes de casar o comando.
- Resolve o dir do repo a partir do `cwd` do **evento** (correto dentro de worktrees).
- **Fail-open** quando uma dependência externa falta (aqui: `gh` ausente/não-autenticado).
- Exit `0` = libera · Exit `2` = bloqueia.
- Seams de teste via env vars (espelha `OLI_DEV_GATE_DIR`/`OLI_DEV_*_CMDS`).

## Componente 1 — `hooks/branch-state-guard.sh`

Fluxo:

1. Parse `tool_input.command` e `cwd` do JSON (reusa o padrão python do pre-push-gate).
2. Strip de env-prefixes `VAR=val ` (sed quote-aware). O comando "core" precisa **começar**
   com `git push` ou `git commit` (`git push`, `git push …`, `git commit`, `git commit …`).
   Qualquer outra coisa → `exit 0`.
3. Resolve `dir`: `OLI_DEV_GUARD_DIR` se setado; senão `git -C <evcwd> rev-parse --show-toplevel`.
4. Branch atual: `OLI_DEV_GUARD_BRANCH` se setado; senão `git -C "$dir" branch --show-current`.
   Se branch for `main`/`master`/vazia → `exit 0` (libera; main não gera órfão de feature).
5. **Anti-órfão (bloqueio):** obtém o `state` da PR da branch como string nua.
   - Comando: `OLI_DEV_GUARD_GH_CMD` se setado; senão
     `gh pr view "$branch" --json state -q .state 2>/dev/null`. O `-q` é o jq embutido do
     próprio `gh` (não exige `jq` no sistema) e devolve só a string (`MERGED`, `OPEN`, …)
     no stdout. O seam de teste simplesmente ecoa a string desejada.
   - Se o comando **falha** (rc≠0) **ou** o stdout vem vazio (`gh` ausente, não-autenticado,
     sem PR pra branch, offline) → **fail-open**: `exit 0` + aviso no stderr.
   - Se `state == MERGED` → **`exit 2`** com mensagem:
     `"BLOQUEADO: a PR da branch '<branch>' já está MERGED — commits/pushes aqui ficam órfãos.
     Crie uma branch nova a partir da main."`
   - Qualquer outro estado (`OPEN`, `CLOSED`, etc.) → `exit 0`.

   **Semântica "PR mais recente vence" (decisão consciente):** `gh pr view <branch>` resolve a
   PR **mais recente** criada para a branch, não necessariamente a mergeada. Consequência: o
   guard fecha a janela perigosa "PR mergeada, branch ainda não apagada, **sem PR mais nova**".
   Se já existe uma PR OPEN mais nova sobre a mesma branch, `state` vem `OPEN` e o guard libera —
   o que é **correto**: uma PR aberta nova significa que os commits têm destino, não são órfãos.
   Isto é intencional; há um teste para o caso (MERGED antiga + OPEN nova → libera).
6. **Aviso de worktree (não-bloqueio):** detecta worktree linkado comparando
   `git -C "$dir" rev-parse --git-dir` com `git -C "$dir" rev-parse --git-common-dir`
   (resolvidos a caminho absoluto). Se forem **iguais** → checkout principal (não worktree).
   Override via `OLI_DEV_GUARD_IN_WORKTREE` (`1` ⇒ worktree linkado ⇒ sem aviso; `0` ⇒ checkout
   principal). Se for checkout principal **e** a branch é feature (não main/master) → emite aviso
   no stderr sugerindo worktree. **Não** altera o exit code por si só.
   - Edge de submódulo (`git-dir != git-common-dir` também dentro de submódulos): irrelevante
     aqui — no pior caso suprime um aviso (falso-negativo num caminho que só avisa), inofensivo.

### Kill switch / latência

O check anti-órfão faz uma chamada de rede `gh` (~300ms–1.5s) em **todo** `git push` e
`git commit` numa feature branch — custo real numa sessão TDD com muitos commits (decisão do
usuário: cobertura total > latência). Mitigação: `OLI_DEV_GUARD_DISABLE=1` desliga o guard
inteiro (`exit 0` imediato). **Não** adotamos um pré-filtro local "pular `gh` se a branch não
tem upstream/ref remoto": seria incorreto — uma branch apagada no merge perde o ref
`origin/<branch>` local, mas a PR mergeada **continua** visível ao `gh` (é exatamente o caso
que precisamos pegar). Correção > latência: a chamada `gh` fica.

### Interação com o marcador `OLI_DEV_GATE_OK=1`

O marcador in-cycle da Fase 7 **NÃO** dispensa o check anti-órfão. Ele existe só para evitar
re-rodar lint/test no `pre-push-gate`; o estado da branch é uma preocupação diferente e barata.
No caminho feliz isso é inócuo (na Fase 7 a PR ainda não está MERGED → libera). O ganho:
mesmo um push movido pela máquina do ciclo é barrado se a branch já estiver MERGED.

Confirmado contra o fluxo: nem a Fase 7 nem o `finalize` empurram legitimamente para uma branch
já mergeada (Fase 7 abre a PR antes do merge; `finalize` só remove worktree/branch pós-merge, não
dá push). Logo o "não-dispensar" não cria parede em nenhum caminho legítimo.

### Testabilidade (seams)

- `OLI_DEV_GUARD_DIR` — força o dir do repo (evita depender do cwd real).
- `OLI_DEV_GUARD_BRANCH` — força a branch atual (evita depender do git real).
- `OLI_DEV_GUARD_GH_CMD` — substitui a invocação do `gh`. **stdout** = a string de estado que
  o `gh … -q .state` imprimiria (`MERGED`, `OPEN`, …); **rc≠0** ou stdout vazio simula falha
  do `gh` (fail-open).
- `OLI_DEV_GUARD_IN_WORKTREE` — força a detecção de worktree para testar o aviso sem montar um
  worktree real: `1` ⇒ worktree linkado (sem aviso), `0` ⇒ checkout principal (aviso se feature).
- `OLI_DEV_GUARD_DISABLE` — `1` desliga o guard inteiro (`exit 0` imediato).

Os prefixos `OLI_DEV_GATE_*` (do `pre-push-gate.sh`) e `OLI_DEV_GUARD_*` (deste hook) são
**deliberadamente independentes** — são dois hooks distintos no mesmo array PreToolUse/`Bash`;
setar um não afeta o outro.

## Componente 2 — `hooks/hooks.json`

Adiciona um segundo comando ao array `hooks` do bloco PreToolUse/`Bash` existente:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "sh \"${CLAUDE_PLUGIN_ROOT}/hooks/pre-push-gate.sh\"" },
          { "type": "command", "command": "sh \"${CLAUDE_PLUGIN_ROOT}/hooks/branch-state-guard.sh\"" }
        ]
      }
    ]
  }
}
```

## Componente 3 — `tests/test_branch_state_guard.sh`

Espelha `test_pre_push_gate.sh` (helper `gate_rc` + `check`, sem `set -e`). Casos:

1. Comando não-git (`git status`, `echo …`) → `0`.
2. Texto que menciona push mas não é push (`echo lembrar de git push`) → `0`.
3. `git push`/`git commit` em `main` → `0`.
4. `git push` em feature branch com PR **MERGED** → `2`.
5. `git commit -m x` em feature branch com PR **MERGED** → `2`.
6. `git push` em feature branch com PR **OPEN** → `0`.
7. `gh` falha (seam rc≠0) → `0` (fail-open).
8. Push com env-prefix (`FOO=bar git push`) numa branch MERGED → `2` (regressão do strip).
9. `OLI_DEV_GATE_OK=1 git push` numa branch MERGED → `2` (marcador não dispensa anti-órfão).
10. PR `CLOSED` (não mergeada) → `0`.
11. Falso-positivo de prefixo: `git commit-tree …` / `git pushy` numa branch MERGED → `0`
    (não casam o token exato `git commit`/`git push`).
12. PR mais nova OPEN sobre branch com PR antiga MERGED (seam ecoa `OPEN`) → `0`
    (semântica "PR mais recente vence").
13. Branch vazia / detached HEAD (`OLI_DEV_GUARD_BRANCH=""`) → `0`.
14. `OLI_DEV_GUARD_DISABLE=1` em push numa branch MERGED → `0` (kill switch).
15. Aviso de worktree: `OLI_DEV_GUARD_IN_WORKTREE=0` + feature branch + PR OPEN → `0`
    (libera, mas emite aviso no stderr — verificar a string no stderr, não só o rc).

Registrado em `tests/run_all.sh`. Critério: `run_all.sh` ALL GREEN.

## Componente 4 — Docs (Fase 0 reforço)

- `references/setup-gate.md`: novo passo no resume/checkpoint — antes de retomar trabalho numa
  branch existente, checar que (a) estamos num worktree linkado e (b) a PR da branch **não**
  está MERGED; senão, barrar e orientar a criar branch nova da `main`. A enforcement
  determinística vive no hook; isto é a orientação correspondente.
- `SKILL.md`: (opcional) uma linha nos Princípios apontando o guard determinístico.

## Critérios de aceite (do issue #6)

- [ ] Hook bloqueia push/commit numa branch cuja PR está MERGED (testado com seam, sem PR real).
- [ ] Hook não quebra quando `gh` está ausente ou não-autenticado (fail-open + aviso).
- [ ] Hook não bloqueia push em `main` nem em branch com PR aberta.
- [ ] Aviso (não-bloqueio) ao trabalhar no dir principal numa feature branch.
- [ ] Fase 0 recusa retomar numa branch já mergeada.
- [ ] `run_all.sh` ALL GREEN, incluindo `test_branch_state_guard.sh`.

## Fora de escopo (YAGNI)

- Cache do resultado do `gh` (hook é stateless; aceita-se a latência por chamada).
- Bloqueio determinístico por "falta de worktree" (fica como aviso — falsos positivos seriam
  intrusivos demais; o worktree é garantido pela Fase 0).
- Proxy/retry de rede para o `gh`.
- Pré-filtro local pra evitar a chamada `gh` (rejeitado — ver "Kill switch / latência").

## Limitação conhecida (best-effort)

O guard é um **backstop**, não uma garantia. Ele só bloqueia quando o `gh` responde com sucesso
e retorna exatamente `MERGED`. Sempre que o `gh` estiver ausente, não-autenticado, offline,
rate-limited ou lento a ponto de falhar, o guard fica **silenciosamente inerte** (fail-open).
Isso é aceitável: a regra de processo (orientação na Fase 0 + revisão humana) continua valendo;
o hook só adiciona uma rede de segurança determinística quando as condições permitem.

## Notas de plataforma

Windows/Git Bash: `command -v gh`, paths POSIX, sem `jq` (extrair JSON via python).
