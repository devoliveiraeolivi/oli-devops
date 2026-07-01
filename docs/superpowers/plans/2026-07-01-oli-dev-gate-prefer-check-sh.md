# oli-dev pre-push gate prefere `scripts/check.sh` — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fazer o pre-push gate do oli-dev preferir o `scripts/check.sh --fast` do repo (fonte única espelhando o CI) quando existe, com fallback python enxuto e baseline-aware na ausência.

**Architecture:** Uma camada de precedência no início do hook `pre-push-gate.sh` (stack-agnóstica, antes do split python/node); o fallback python perde `black`/`pytest` e ganha detecção de `.mypy-baseline.txt`. Docs e testes acompanham. Node fica intacto.

**Tech Stack:** POSIX sh (hook + testes), Markdown (docs). Sem dependências novas.

## Global Constraints

- **Não quebrar a suíte existente:** `plugins/oli-dev/tests/run_all.sh` deve passar 100% (pré-requisito de tag — golden rule do CLAUDE.md).
- **Não renomear** o hook nem quebrar sua interface (lê o evento PreToolUse no stdin; exit 0 = libera, exit 2 = bloqueia).
- **Escape hatch preservado:** `OLI_DEV_PYTHON_CMDS` / `OLI_DEV_NODE_CMDS`, quando setados, vencem tudo (inclusive check.sh).
- **Escopo:** só o gate no oli-devops. Node fallback inalterado. Template check.sh **fora** de escopo.
- **CHANGELOG.md** atualizado no mesmo commit da mudança de comportamento.
- Testes em POSIX sh, no estilo do harness existente (`gate_rc`, `check`, contadores `pass`/`fail`).

Arquivo alvo do hook: `plugins/oli-dev/hooks/pre-push-gate.sh`
Arquivo de testes: `plugins/oli-dev/tests/test_pre_push_gate.sh`

---

### Task 1: Precedência do `scripts/check.sh`

**Files:**
- Modify: `plugins/oli-dev/hooks/pre-push-gate.sh` (inserir bloco após a resolução de `$dir`, antes do `if [ -f "$dir/pyproject.toml" ]`)
- Test: `plugins/oli-dev/tests/test_pre_push_gate.sh` (anexar casos antes do `echo "pre_push_gate: ..."`)

**Interfaces:**
- Consumes: variáveis já resolvidas no hook — `$dir` (toplevel do repo), `$cmd`, helper `run()` (`echo ">> $1" >&2; sh -c "$1"`), envs `OLI_DEV_PYTHON_CMDS`/`OLI_DEV_NODE_CMDS`.
- Produces: comportamento — se `$dir/scripts/check.sh` é executável e nenhum `*_CMDS` está setado, o gate roda `scripts/check.sh --fast` e retorna 0/2; caso contrário cai no fluxo atual.

- [ ] **Step 1: Escrever os testes que falham** (anexar em `plugins/oli-dev/tests/test_pre_push_gate.sh`, logo antes da linha `echo "pre_push_gate: $pass passed, $fail failed"`)

```sh
# 7. scripts/check.sh presente + falhando → gate o prefere e bloqueia (exit 2),
#    mesmo o fallback python passando.
mkdir -p "$TMP/withcheck/scripts"; printf '[project]\nname="x"\n' > "$TMP/withcheck/pyproject.toml"
printf '#!/bin/sh\nexit 1\n' > "$TMP/withcheck/scripts/check.sh"; chmod +x "$TMP/withcheck/scripts/check.sh"
check "$(gate_rc '{"tool_input":{"command":"git push"}}' OLI_DEV_GATE_DIR="$TMP/withcheck")" 2 "check.sh falhando bloqueia (preferido sobre fallback)"

# 8. scripts/check.sh presente + passando → gate roda e libera; marcador prova que rodou.
mkdir -p "$TMP/checkok/scripts"
printf '#!/bin/sh\ntouch "%s/checkok/ran"\nexit 0\n' "$TMP" > "$TMP/checkok/scripts/check.sh"; chmod +x "$TMP/checkok/scripts/check.sh"
check "$(gate_rc '{"tool_input":{"command":"git push"}}' OLI_DEV_GATE_DIR="$TMP/checkok")" 0 "check.sh passando libera"
if [ -f "$TMP/checkok/ran" ]; then pass=$((pass+1)); else echo "FAIL: check.sh realmente rodou (marcador ausente)" >&2; fail=$((fail+1)); fi

# 9. Override explícito OLI_DEV_PYTHON_CMDS vence o check.sh (escape hatch).
mkdir -p "$TMP/override/scripts"; printf '[project]\nname="x"\n' > "$TMP/override/pyproject.toml"
printf '#!/bin/sh\nexit 1\n' > "$TMP/override/scripts/check.sh"; chmod +x "$TMP/override/scripts/check.sh"
check "$(gate_rc '{"tool_input":{"command":"git push"}}' OLI_DEV_GATE_DIR="$TMP/override" OLI_DEV_PYTHON_CMDS=true)" 0 "override vence check.sh"
```

- [ ] **Step 2: Rodar os testes e confirmar que falham**

Run: `sh plugins/oli-dev/tests/test_pre_push_gate.sh`
Expected: FAIL — o caso 7 dá `rc=2` esperado mas o gate atual retorna `2` só se o fallback `false`… na verdade o gate atual **não** conhece check.sh, então em `$TMP/withcheck` (pyproject presente, sem `OLI_DEV_PYTHON_CMDS`) ele tenta `uv run …`; se `uv` faltar, degrada para `exit 0` → caso 7 falha (quer 2, obtém 0). Casos 8/9 idem. Confirme pelo menos um FAIL na saída.

- [ ] **Step 3: Implementar a precedência no hook**

Em `plugins/oli-dev/hooks/pre-push-gate.sh`, logo **após** o bloco que resolve `$dir` (a linha `dir="$(...)"` / fim do `if [ -n "${OLI_DEV_GATE_DIR:-}" ]`) e **antes** de `run() { ... }` não — inserir **depois** da definição de `run()` e **antes** do `if [ -f "$dir/pyproject.toml" ]`:

```sh
# Gate próprio do repo (espelho do CI, fonte única) vence — a menos que um
# override *_CMDS esteja setado (escape hatch + determinismo de teste).
if [ -z "${OLI_DEV_PYTHON_CMDS:-}${OLI_DEV_NODE_CMDS:-}" ] && [ -x "$dir/scripts/check.sh" ]; then
  cd "$dir" || exit 0
  if ! run "scripts/check.sh --fast"; then
    echo "BLOQUEADO: scripts/check.sh --fast falhou em $dir. Corrija antes de dar push." >&2
    exit 2
  fi
  exit 0
fi
```

- [ ] **Step 4: Rodar os testes e confirmar que passam**

Run: `sh plugins/oli-dev/tests/test_pre_push_gate.sh`
Expected: PASS — todos os casos (1–6 antigos + 7/8/9 novos), `pre_push_gate: N passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/oli-dev/hooks/pre-push-gate.sh plugins/oli-dev/tests/test_pre_push_gate.sh
git commit -m "feat(oli-dev): pre-push gate prefere scripts/check.sh --fast

Se o repo tem scripts/check.sh executável (espelho do CI), o gate o roda em
vez do conjunto hardcoded — fonte única, mata divergência e double-run.
Override OLI_DEV_*_CMDS ainda vence (escape hatch).

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Fallback python enxuto + baseline-aware

**Files:**
- Modify: `plugins/oli-dev/hooks/pre-push-gate.sh` (o bloco `if [ -f "$dir/pyproject.toml" ]`)
- Test: `plugins/oli-dev/tests/test_pre_push_gate.sh` (helper `gate_err` + fake `uv` + casos 10–12)

**Interfaces:**
- Consumes: `$dir`, `run()`, `OLI_DEV_PYTHON_CMDS`.
- Produces: comando default do fallback python = `uv run ruff check src/ && uv run ruff format --check src/ tests/ && <mypy>`, onde `<mypy>` é `uv run mypy src/ | uv run mypy-baseline filter --baseline-path .mypy-baseline.txt --allow-unsynced` se `.mypy-baseline.txt` existe e `uv run mypy-baseline` resolve, senão `uv run mypy src/`. Sem `black`, sem `pytest`.

- [ ] **Step 1: Escrever os testes que falham** (anexar em `test_pre_push_gate.sh`, antes do `echo` final; adicionar os dois helpers uma única vez perto do topo, junto aos existentes)

Helpers (colocar logo após a definição de `gate_rc`/`check`, linha ~12):

```sh
# captura só o stderr do gate (o run() ecoa ">> <cmd>" em stderr antes de executar)
gate_err() { json="$1"; shift; printf '%s' "$json" | env "$@" sh "$GATE" 2>&1 >/dev/null; }
# fake uv: sempre sai 0 → deixa o gate compor+ecoar o cmd sem toolchain real
mkdir -p "$TMP/bin"; printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/uv"; chmod +x "$TMP/bin/uv"
```

Casos (antes do `echo` final):

```sh
# 10. Fallback (sem check.sh): cmd composto tira black, mantém ruff format + mypy.
mkdir -p "$TMP/fb"; printf '[project]\nname="x"\n' > "$TMP/fb/pyproject.toml"
err10="$(gate_err '{"tool_input":{"command":"git push"}}' OLI_DEV_GATE_DIR="$TMP/fb" PATH="$TMP/bin:$PATH")"
if echo "$err10" | grep -q 'ruff format'; then pass=$((pass+1)); else echo "FAIL: fallback roda ruff format" >&2; fail=$((fail+1)); fi
if echo "$err10" | grep -q 'black'; then echo "FAIL: fallback não pode rodar black" >&2; fail=$((fail+1)); else pass=$((pass+1)); fi

# 11. Fallback mypy baseline-aware quando há .mypy-baseline.txt.
mkdir -p "$TMP/fbbl"; printf '[project]\nname="x"\n' > "$TMP/fbbl/pyproject.toml"; : > "$TMP/fbbl/.mypy-baseline.txt"
err11="$(gate_err '{"tool_input":{"command":"git push"}}' OLI_DEV_GATE_DIR="$TMP/fbbl" PATH="$TMP/bin:$PATH")"
if echo "$err11" | grep -q 'mypy-baseline filter'; then pass=$((pass+1)); else echo "FAIL: baseline presente → mypy-baseline filter" >&2; fail=$((fail+1)); fi

# 12. Fallback mypy cru quando NÃO há baseline.
err12="$(gate_err '{"tool_input":{"command":"git push"}}' OLI_DEV_GATE_DIR="$TMP/fb" PATH="$TMP/bin:$PATH")"
if echo "$err12" | grep -q 'mypy-baseline filter'; then echo "FAIL: sem baseline → mypy cru" >&2; fail=$((fail+1)); else pass=$((pass+1)); fi
```

- [ ] **Step 2: Rodar e confirmar que falham**

Run: `sh plugins/oli-dev/tests/test_pre_push_gate.sh`
Expected: FAIL — o fallback atual compõe `uv run black --check src/ tests/ && uv run ruff check src/ && uv run pytest tests/unit/ -q && uv run mypy src/`, então o caso 10 acha `black` (FAIL) e o caso 11 não acha `mypy-baseline filter` (FAIL).

- [ ] **Step 3: Implementar o fallback enxuto**

Substituir, no bloco `if [ -f "$dir/pyproject.toml" ]`, a montagem do `cmds` e ordem do `cd`. O bloco inteiro passa a ser:

```sh
if [ -f "$dir/pyproject.toml" ]; then
  if ! command -v uv >/dev/null 2>&1 && [ -z "${OLI_DEV_PYTHON_CMDS:-}" ]; then
    echo "oli-dev gate: 'uv' não está no PATH — pulando checagem python em $dir." >&2; exit 0
  fi
  cd "$dir" || exit 0
  if [ -n "${OLI_DEV_PYTHON_CMDS:-}" ]; then
    cmds="$OLI_DEV_PYTHON_CMDS"
  else
    # mypy baseline-aware: com baseline, só falha em erro NOVO (igual ao CI).
    if [ -f ".mypy-baseline.txt" ] && uv run mypy-baseline --version >/dev/null 2>&1; then
      mypy_cmd="uv run mypy src/ | uv run mypy-baseline filter --baseline-path .mypy-baseline.txt --allow-unsynced"
    else
      mypy_cmd="uv run mypy src/"
    fi
    # Sem black (legado → ruff format) e sem pytest (já roda no verify da Fase 5).
    cmds="uv run ruff check src/ && uv run ruff format --check src/ tests/ && $mypy_cmd"
  fi
  if ! run "$cmds"; then
    echo "BLOQUEADO: pre-push gate (python) falhou em $dir. Corrija antes de dar push." >&2
    exit 2
  fi
  exit 0
fi
```

- [ ] **Step 4: Rodar e confirmar que passam**

Run: `sh plugins/oli-dev/tests/test_pre_push_gate.sh`
Expected: PASS — `pre_push_gate: N passed, 0 failed` (casos 1–12).

- [ ] **Step 5: Rodar a suíte inteira do plugin**

Run: `sh plugins/oli-dev/tests/run_all.sh`
Expected: todas as suítes verdes (nenhum FAIL).

- [ ] **Step 6: Commit**

```bash
git add plugins/oli-dev/hooks/pre-push-gate.sh plugins/oli-dev/tests/test_pre_push_gate.sh
git commit -m "feat(oli-dev): fallback python do gate enxuto + baseline-aware

Sem check.sh, o fallback roda ruff check + ruff format --check + mypy — sem
black (legado) e sem pytest (já roda no verify da Fase 5). mypy vira
baseline-aware quando há .mypy-baseline.txt (corrige falso-bloqueio).

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Docs + CHANGELOG

**Files:**
- Modify: `plugins/oli-dev/skills/dev-cycle/references/pre-push-gate.md`
- Modify: `plugins/oli-dev/skills/dev-cycle/SKILL.md` (linha da Fase 6, ~46)
- Modify: `CHANGELOG.md` (seção `[Unreleased]`)

**Interfaces:**
- Consumes: nada (docs).
- Produces: docs consistentes com o comportamento novo.

- [ ] **Step 1: Reescrever o bullet Python do reference**

Em `plugins/oli-dev/skills/dev-cycle/references/pre-push-gate.md`, substituir o bullet **Python** atual por:

```markdown
- **Python** (`pyproject.toml`):
  - Se existe `scripts/check.sh` no repo → rode **`scripts/check.sh --fast`** (fonte
    única que espelha o `ci.yml`). É o mesmo comando do `.githooks/pre-push` do repo.
  - Senão (fallback): `uv run ruff check src/` · `uv run ruff format --check src/ tests/` ·
    `uv run mypy src/` (baseline-aware: se há `.mypy-baseline.txt`, filtra pelo baseline,
    igual ao CI). **Sem `black`** (legado → `ruff format`) e **sem `pytest`** (os testes já
    rodaram no `verify` da Fase 5).
```

- [ ] **Step 2: Atualizar a linha da Fase 6 no SKILL.md**

Em `plugins/oli-dev/skills/dev-cycle/SKILL.md`, na linha da **Fase 6** (~46), trocar:

`- **Fase 6 — PRE-PUSH gate** → ver \`references/pre-push-gate.md\`. black+ruff+pytest+mypy (ou lint+test+build). Bloqueia se falhar, com evidência.`

por:

`- **Fase 6 — PRE-PUSH gate** → ver \`references/pre-push-gate.md\`. Prefere \`scripts/check.sh --fast\` do repo; senão fallback ruff+mypy (ou lint+test+build p/ node). Bloqueia se falhar, com evidência.`

- [ ] **Step 3: Entrada no CHANGELOG**

Em `CHANGELOG.md`, dentro de `## [Unreleased]`, na subseção `### Changed` (criar se não existir, no topo da `[Unreleased]`), adicionar:

```markdown
- **`oli-dev` pre-push gate prefere `scripts/check.sh`**: o gate da Fase 6 e o backstop
  `hooks/pre-push-gate.sh` agora rodam `scripts/check.sh --fast` do repo quando existe (fonte
  única espelhando o CI). Fallback (sem check.sh) enxuto: `ruff check` + `ruff format --check` +
  `mypy` baseline-aware — sem `black` (legado) e sem `pytest` (já roda no `verify` da Fase 5).
  Corrige falso-bloqueio do mypy baseline e o double-run com o `.githooks/pre-push` do repo.
  Override `OLI_DEV_*_CMDS` ainda vence. Node inalterado.
```

- [ ] **Step 4: Rodar a suíte (garante que docs/manifests não quebraram)**

Run: `sh plugins/oli-dev/tests/run_all.sh`
Expected: todas as suítes verdes (incl. `test_references.sh`, `test_skill_structure.sh`).

- [ ] **Step 5: Commit**

```bash
git add plugins/oli-dev/skills/dev-cycle/references/pre-push-gate.md plugins/oli-dev/skills/dev-cycle/SKILL.md CHANGELOG.md
git commit -m "docs(oli-dev): gate prefere check.sh (reference + SKILL + CHANGELOG)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- check.sh preferido → Task 1. ✓
- Fallback enxuto (sem black/pytest) → Task 2. ✓
- mypy baseline-aware → Task 2. ✓
- Precedência override > check.sh > fallback → Task 1 (guard) + Task 2. ✓
- Docs (reference + SKILL) → Task 3. ✓
- Testes → Tasks 1 e 2. ✓
- CHANGELOG → Task 3. ✓
- Node intacto / template fora de escopo → nenhuma task toca. ✓

**Placeholder scan:** nenhum TBD/TODO; todo passo tem código/comando concreto e saída esperada.

**Type/consistency:** nomes de env (`OLI_DEV_PYTHON_CMDS`, `OLI_DEV_NODE_CMDS`, `OLI_DEV_GATE_DIR`), helper `run()`, e o comando `scripts/check.sh --fast` são idênticos entre tasks e batem com o hook atual e o `check.sh` do oli-indexer.
