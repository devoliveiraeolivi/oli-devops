# oli-dev Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `oli-dev` Claude Code plugin in the `oli-devops` repo — a thin opinionated maestro that conducts the OLI development cycle (worktree → brainstorm → review → plan → TDD write → review → pre-push gate → PR → finalize) by chaining existing superpowers skills, with hard process gates.

**Architecture:** A plugin = a marketplace entry + a manifest + one slash command (entry) + one "glue" skill (`dev-cycle`) using progressive disclosure (lean `SKILL.md` + `references/` + `assets/`) + a deterministic pre-push hook + self-evals. The plugin does NOT reimplement superpowers; it invokes it. Source of truth for all behavior is the spec at `docs/superpowers/specs/2026-06-24-oli-dev-plugin-design.md`.

**Tech Stack:** Markdown (skill/command/docs), JSON (plugin/marketplace/hooks/evals manifests), POSIX shell run in Git Bash (pre-push gate hook). No build step, no package manager.

## Global Constraints

- **Spec is authoritative:** every behavior described here must match `docs/superpowers/specs/2026-06-24-oli-dev-plugin-design.md`. When in doubt, read the spec section cited in the task.
- **Plugin name:** `oli-dev`. **Skill name:** `dev-cycle`. **Command:** `/oli-dev`. Use these exact identifiers everywhere.
- **Plugin root path:** `plugins/oli-dev/` inside the `oli-devops` repo. Marketplace manifest at repo root `.claude-plugin/marketplace.json`.
- **Hooks use `${CLAUDE_PLUGIN_ROOT}`** to reference bundled scripts (never hardcode absolute paths).
- **Shell scripts are POSIX `sh`, run in Git Bash on Windows.** Use `command -v` for tool probes; never assume `jq`/`uv`/`npm` exist. Degrade with a warning when a tool is absent; only block on a check that ran and failed.
- **Pre-push gate exit codes:** `0` = pass OR unrecognized stack (don't block what we can't check); `2` = a check ran and failed (blocks the push; stderr is fed back to the agent).
- **The 4 process principles (spec "Princípios de processo") are invioláveis:** (1) one branch per cycle from `main`, no stacked PRs by default; (2) worktree always, from `main`; (3) never delete a branch without `gh pr view --json state == MERGED`; (4) every review subagent runs on Opus 4.8 (`model: "opus"`).
- **Language:** all user-facing content in Portuguese (matches the OLI repos), code identifiers/keys in English where conventional.
- **Commits:** frequent, conventional-commit style, end body with `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- **This work runs in the already-created worktree** `.worktrees/oli-dev-plugin` on branch `feat/oli-dev-plugin`. Do NOT create a new worktree.

---

### Task 1: Plugin scaffold + manifests

Make the plugin installable (valid, even if empty of behavior). This locks in identifiers and directory layout.

**Files:**
- Create: `.claude-plugin/marketplace.json` (repo root)
- Create: `plugins/oli-dev/.claude-plugin/plugin.json`
- Test: `plugins/oli-dev/tests/test_manifests.sh`

**Interfaces:**
- Produces: plugin identifier `oli-dev`, version `0.1.0`; marketplace name `oli-devops`; the `plugins/oli-dev/` tree root that every later task writes into.

- [ ] **Step 1: Write the failing test**

```bash
# plugins/oli-dev/tests/test_manifests.sh
#!/usr/bin/env sh
set -eu
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"   # repo root
fail() { echo "FAIL: $1" >&2; exit 1; }

# JSON validity (python is always present in these repos)
python -c "import json,sys; json.load(open('$ROOT/.claude-plugin/marketplace.json'))" \
  || fail "marketplace.json is not valid JSON"
python -c "import json,sys; json.load(open('$ROOT/plugins/oli-dev/.claude-plugin/plugin.json'))" \
  || fail "plugin.json is not valid JSON"

# Required fields
python - "$ROOT" <<'PY'
import json, sys
root = sys.argv[1]
mk = json.load(open(f"{root}/.claude-plugin/marketplace.json"))
assert mk.get("name") == "oli-devops", mk.get("name")
plugins = mk.get("plugins", [])
assert any(p.get("name") == "oli-dev" for p in plugins), "oli-dev not registered in marketplace"
pj = json.load(open(f"{root}/plugins/oli-dev/.claude-plugin/plugin.json"))
assert pj.get("name") == "oli-dev", pj.get("name")
assert "version" in pj and "description" in pj
print("OK manifests")
PY
echo "PASS test_manifests"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh plugins/oli-dev/tests/test_manifests.sh`
Expected: FAIL — files don't exist yet (`No such file or directory`).

- [ ] **Step 3: Write the manifests**

```json
// .claude-plugin/marketplace.json
{
  "name": "oli-devops",
  "owner": { "name": "devoliveiraeolivi" },
  "plugins": [
    {
      "name": "oli-dev",
      "source": "./plugins/oli-dev",
      "description": "Maestro do ciclo de desenvolvimento OLI: worktree, brainstorm, review, plano, escrita TDD, review, pre-push gate, PR e finalize."
    }
  ]
}
```

```json
// plugins/oli-dev/.claude-plugin/plugin.json
{
  "name": "oli-dev",
  "version": "0.1.0",
  "description": "Conduz o ciclo de desenvolvimento OLI encadeando skills do superpowers com gates opinativos (worktree sempre, Opus nos reviews, pre-push obrigatório, finalize pós-merge). Depende do plugin superpowers.",
  "author": { "name": "devoliveiraeolivi" },
  "homepage": "https://github.com/devoliveiraeolivi/oli-devops",
  "keywords": ["workflow", "tdd", "code-review", "worktree", "orchestration", "oli"]
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `sh plugins/oli-dev/tests/test_manifests.sh`
Expected: `OK manifests` then `PASS test_manifests`.

- [ ] **Step 5: Commit**

```bash
git add .claude-plugin/marketplace.json plugins/oli-dev/.claude-plugin/plugin.json plugins/oli-dev/tests/test_manifests.sh
git commit -m "feat(oli-dev): scaffold do plugin + manifestos (marketplace + plugin.json)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Pre-push gate hook (stack detection + exit codes)

The only real logic in the plugin. TDD it hard: stack detection and blocking behavior. Spec §5.

**Files:**
- Create: `plugins/oli-dev/hooks/pre-push-gate.sh`
- Create: `plugins/oli-dev/hooks/hooks.json`
- Test: `plugins/oli-dev/tests/test_pre_push_gate.sh`

**Interfaces:**
- Consumes: nothing from earlier tasks (self-contained).
- Produces: `pre-push-gate.sh` contract — reads the PreToolUse JSON event on stdin; if `tool_input.command` does not contain `git push`, exits `0` immediately; otherwise detects stack in `$CLAUDE_PROJECT_DIR` (fallback: cwd) and runs the gate. Env override `OLI_DEV_GATE_DIR` forces the dir to check (used by tests). Stack detection: `pyproject.toml` → python gate; `package.json` → node gate; neither → exit `0` with a notice. Exit `2` only when a check that ran returned non-zero.

- [ ] **Step 1: Write the failing test**

```bash
# plugins/oli-dev/tests/test_pre_push_gate.sh
#!/usr/bin/env sh
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="$HERE/../hooks/pre-push-gate.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
check() { if [ "$1" = "$2" ]; then pass=$((pass+1)); else echo "FAIL: $3 (got rc=$1, want $2)" >&2; fail=$((fail+1)); fi; }

# 1. Non-push command → exit 0 without running anything
echo '{"tool_input":{"command":"git status"}}' | sh "$GATE"; check $? 0 "non-push passes through"

# 2. Push in an unrecognized stack dir → exit 0 (don't block what we can't check)
mkdir -p "$TMP/empty"
echo '{"tool_input":{"command":"git push origin main"}}' | OLI_DEV_GATE_DIR="$TMP/empty" sh "$GATE"; check $? 0 "unknown stack passes"

# 3. Push in a python stack whose checks FAIL → exit 2
mkdir -p "$TMP/py"
printf '[project]\nname="x"\n' > "$TMP/py/pyproject.toml"
# Force the gate to use a failing command set via override hooks (see script: OLI_DEV_PYTHON_CMDS)
echo '{"tool_input":{"command":"git push"}}' | OLI_DEV_GATE_DIR="$TMP/py" OLI_DEV_PYTHON_CMDS="false" sh "$GATE"; check $? 2 "python failing check blocks"

# 4. Push in a python stack whose checks PASS → exit 0
echo '{"tool_input":{"command":"git push"}}' | OLI_DEV_GATE_DIR="$TMP/py" OLI_DEV_PYTHON_CMDS="true" sh "$GATE"; check $? 0 "python passing check allows"

echo "pre_push_gate: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh plugins/oli-dev/tests/test_pre_push_gate.sh`
Expected: FAIL — `pre-push-gate.sh` does not exist.

- [ ] **Step 3: Write the hook script**

```bash
# plugins/oli-dev/hooks/pre-push-gate.sh
#!/usr/bin/env sh
# Pre-push gate (backstop). Reads PreToolUse event JSON on stdin.
# Exit 0 = allow (pass or unrecognized stack); exit 2 = block (a check failed).
set -u

stdin="$(cat 2>/dev/null || true)"
case "$stdin" in
  *'git push'*) : ;;            # it's a push → run the gate
  *) exit 0 ;;                  # not a push → allow
esac

dir="${OLI_DEV_GATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}}"

run() {  # run a command, echo a banner, return its rc
  echo ">> $1" >&2
  sh -c "$1"
}

if [ -f "$dir/pyproject.toml" ]; then
  # Test seam: OLI_DEV_PYTHON_CMDS overrides the real command list.
  cmds="${OLI_DEV_PYTHON_CMDS:-}"
  if [ -z "$cmds" ]; then
    cmds="uv run black --check src/ tests/ && uv run ruff check src/ && uv run pytest tests/unit/ -q && uv run mypy src/"
  fi
  cd "$dir" || exit 0
  if ! run "$cmds"; then
    echo "BLOQUEADO: pre-push gate (python) falhou em $dir. Corrija antes de dar push." >&2
    exit 2
  fi
  exit 0
fi

if [ -f "$dir/package.json" ]; then
  cmds="${OLI_DEV_NODE_CMDS:-}"
  if [ -z "$cmds" ]; then
    cmds="npm run -s lint && npm test --silent && npm run -s build"
  fi
  cd "$dir" || exit 0
  if ! run "$cmds"; then
    echo "BLOQUEADO: pre-push gate (node) falhou em $dir. Corrija antes de dar push." >&2
    exit 2
  fi
  exit 0
fi

echo "oli-dev pre-push gate: stack não reconhecida em $dir — push liberado sem checagem." >&2
exit 0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `sh plugins/oli-dev/tests/test_pre_push_gate.sh`
Expected: `pre_push_gate: 4 passed, 0 failed`.

- [ ] **Step 5: Write the hooks manifest**

```json
// plugins/oli-dev/hooks/hooks.json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "sh \"${CLAUDE_PLUGIN_ROOT}/hooks/pre-push-gate.sh\"" }
        ]
      }
    ]
  }
}
```

- [ ] **Step 6: Validate hooks.json + commit**

Run: `python -c "import json; json.load(open('plugins/oli-dev/hooks/hooks.json')); print('OK hooks.json')"`
Expected: `OK hooks.json`

```bash
git add plugins/oli-dev/hooks/ plugins/oli-dev/tests/test_pre_push_gate.sh
git commit -m "feat(oli-dev): hook de pre-push (deteccao de stack + exit 2 bloqueante)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: The `dev-cycle` skill (lean conductor) + entry command

The glue. A lean `SKILL.md` (just the phase graph + the 4 fixed sections) plus the `/oli-dev` command. Detail lives in `references/` (Task 4). Spec §3, §4, §6.

**Files:**
- Create: `plugins/oli-dev/skills/dev-cycle/SKILL.md`
- Create: `plugins/oli-dev/commands/oli-dev.md`
- Test: `plugins/oli-dev/tests/test_skill_structure.sh`

**Interfaces:**
- Consumes: plugin identifiers from Task 1.
- Produces: skill `dev-cycle` whose body has sections `## When to Use`, `## Prerequisites`, `## Workflow`, `## Verification`, references the 4 process principles, and links to `references/{setup-gate,review-gates,pre-push-gate,finalize}.md` (created in Task 4). Command `oli-dev.md` dispatches to the skill in two modes (`<ideia>` → phases 0–7; `finalize` → phase 8).

- [ ] **Step 1: Write the failing test**

```bash
# plugins/oli-dev/tests/test_skill_structure.sh
#!/usr/bin/env sh
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
SK="$HERE/../skills/dev-cycle/SKILL.md"
CMD="$HERE/../commands/oli-dev.md"
fail() { echo "FAIL: $1" >&2; exit 1; }

[ -f "$SK" ] || fail "SKILL.md missing"
[ -f "$CMD" ] || fail "oli-dev.md command missing"
# YAML frontmatter with name + description
head -1 "$SK" | grep -q '^---$' || fail "SKILL.md missing frontmatter"
grep -q '^name: dev-cycle$' "$SK" || fail "skill name not dev-cycle"
grep -q '^description:' "$SK" || fail "skill missing description"
# 4 fixed body sections
for s in "## When to Use" "## Prerequisites" "## Workflow" "## Verification"; do
  grep -qF "$s" "$SK" || fail "missing section: $s"
done
# References wired (progressive disclosure)
for r in setup-gate review-gates pre-push-gate finalize; do
  grep -qF "references/$r.md" "$SK" || fail "SKILL.md does not link references/$r.md"
done
# The 8 phases are listed
for p in "Fase 0" "Fase 1" "Fase 2" "Fase 3" "Fase 4" "Fase 5" "Fase 6" "Fase 7" "Fase 8"; do
  grep -qF "$p" "$SK" || fail "missing $p in workflow"
done
# Command declares both modes
grep -qF "finalize" "$CMD" || fail "command missing finalize mode"
echo "PASS test_skill_structure"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh plugins/oli-dev/tests/test_skill_structure.sh`
Expected: FAIL — `SKILL.md missing`.

- [ ] **Step 3: Write the command**

```markdown
<!-- plugins/oli-dev/commands/oli-dev.md -->
---
name: oli-dev
description: Roda o ciclo de desenvolvimento OLI (worktree → brainstorm → review → plano → escrita TDD → review → pre-push → PR). Use `/oli-dev <ideia>` para iniciar o ciclo, ou `/oli-dev finalize` para a limpeza pós-merge.
---

Argumentos recebidos: `$ARGUMENTS`

Invoque a skill `dev-cycle` (plugin oli-dev) e siga-a à risca.

- Se `$ARGUMENTS` começar com `finalize` → modo **finalize** (apenas Fase 8: close-out + limpeza pós-merge).
- Caso contrário, trate `$ARGUMENTS` como a descrição da feature → modo **ciclo** (Fases 0–7).

Não pule fases nem gates. Os 4 Princípios de processo do spec são invioláveis.
```

- [ ] **Step 4: Write the lean SKILL.md**

Write `plugins/oli-dev/skills/dev-cycle/SKILL.md` with this exact structure (content derived from spec §4; keep it lean — the operational detail goes in `references/`):

````markdown
---
name: dev-cycle
description: Use ao construir uma feature/mudança nova no ecossistema OLI — conduz o ciclo completo (worktree da main, brainstorm, review staff cético, plano, escrita TDD por subagente Opus, review code/simplify/verify, pre-push gate, PR, finalize pós-merge). Invocada por `/oli-dev <ideia>` e `/oli-dev finalize`.
---

# dev-cycle — maestro do ciclo de desenvolvimento OLI

## When to Use

- `/oli-dev <ideia>` → ciclo completo (Fases 0–7), termina em PR aberta.
- `/oli-dev finalize` → só a Fase 8 (close-out + limpeza), depois que a PR foi mergeada.
- Ative também quando o usuário descreve uma feature nova e pede para "construir/implementar".

NÃO use para: hotfix trivial de 1 linha já aprovado, perguntas, ou tarefas sem código.

## Prerequisites

- Plugin **superpowers** instalado (esta skill o invoca). Se faltar, avise e pare.
- Loop principal em **Opus 4.8** (verificado na Fase 0).
- Repo alvo é um git repo com `main` e remoto configurado.

## Princípios de processo (gates duros — invioláveis)

1. Uma branch por ciclo, **da `main`**. Sem PRs stacked por padrão.
2. **Worktree sempre, da `main`.** Nunca trabalhar direto numa branch no dir principal.
3. **Nunca deletar branch** sem `gh pr view <n> --json state` == `MERGED`.
4. **Todo review no Opus 4.8** (subagentes com `model: "opus"`, effort alto).

## Workflow

Mantenha um todo por fase. Modo `<ideia>` = Fases 0–7; modo `finalize` = Fase 8.
Carregue o `references/*.md` da fase **quando ela começa** (progressive disclosure).

- **Fase 0 — SETUP gate** → ver `references/setup-gate.md`. Checa Opus + deps + cria worktree da main. Resume/checkpoint: detecta spec/plano existentes e retoma da fase certa (pede confirmação antes de pular).
- **Fase 1 — BRAINSTORM** → invoca `superpowers:brainstorming`. Spec em `docs/superpowers/specs/`. Commit.
- **Fase 2 — REVIEW pré-código** → ver `references/review-gates.md`. 1 `staff-reviewer` cético em Opus. Resolve achados. Commit.
- **Fase 3 — PLANO** → invoca `superpowers:writing-plans`. Commit.
- **Fase 4 — ESCRITA** → invoca `superpowers:subagent-driven-development`; cada task em TDD, subagentes Opus. Pipeline (serial) ou Fan-out (`dispatching-parallel-agents`) conforme dependência. Checkpoint commit por task.
- **Fase 5 — REVIEW pós-código** → ver `references/review-gates.md`. `/code-review` → `/simplify` → `verify`; sub-gate condicional `/security-review` se o diff toca superfície sensível. Tudo em Opus.
- **Fase 6 — PRE-PUSH gate** → ver `references/pre-push-gate.md`. black+ruff+pytest+mypy (ou lint+test+build). Bloqueia se falhar, com evidência.
- **Fase 7 — PUSH + PR** → `commit-commands:commit-push-pr`. Base = `main`. Usa `assets/pr-body-template.md`. Termina aqui.
- **Fase 8 — FINALIZE** (`/oli-dev finalize`) → ver `references/finalize.md`. Verifica `MERGED`, limpa worktree+branch, close-out (`assets/close-out-checklist.md`).

## Verification

Antes de declarar qualquer fase concluída, confirme com **evidência** (output real, nunca alegação):
- Fase 0: worktree existe e está na branch certa (`git worktree list`, `git branch --show-current`).
- Fase 2/5: o review rodou em Opus e os achados materiais foram resolvidos.
- Fase 6: os comandos do gate passaram (cole o output).
- Fase 7: a PR foi criada (URL).
- Fase 8: `gh pr view --json state` == `MERGED` antes de qualquer delete; worktree removido; close-out feito.
````

- [ ] **Step 5: Run test to verify it passes**

Run: `sh plugins/oli-dev/tests/test_skill_structure.sh`
Expected: `PASS test_skill_structure`.

- [ ] **Step 6: Commit**

```bash
git add plugins/oli-dev/skills/dev-cycle/SKILL.md plugins/oli-dev/commands/oli-dev.md plugins/oli-dev/tests/test_skill_structure.sh
git commit -m "feat(oli-dev): skill dev-cycle (conductor magro) + comando /oli-dev

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Reference docs (progressive disclosure) + assets

The just-in-time detail for each gate, plus the PR/close-out templates. Spec §2.3, §4, §5.

**Files:**
- Create: `plugins/oli-dev/skills/dev-cycle/references/setup-gate.md`
- Create: `plugins/oli-dev/skills/dev-cycle/references/review-gates.md`
- Create: `plugins/oli-dev/skills/dev-cycle/references/pre-push-gate.md`
- Create: `plugins/oli-dev/skills/dev-cycle/references/finalize.md`
- Create: `plugins/oli-dev/skills/dev-cycle/assets/pr-body-template.md`
- Create: `plugins/oli-dev/skills/dev-cycle/assets/close-out-checklist.md`
- Test: `plugins/oli-dev/tests/test_references.sh`

**Interfaces:**
- Consumes: the reference filenames linked by `SKILL.md` (Task 3).
- Produces: every `references/*.md` linked from `SKILL.md` exists and contains its gate's operational steps; assets exist.

- [ ] **Step 1: Write the failing test**

```bash
# plugins/oli-dev/tests/test_references.sh
#!/usr/bin/env sh
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
BASE="$HERE/../skills/dev-cycle"
fail() { echo "FAIL: $1" >&2; exit 1; }

for f in references/setup-gate.md references/review-gates.md references/pre-push-gate.md \
         references/finalize.md assets/pr-body-template.md assets/close-out-checklist.md; do
  [ -s "$BASE/$f" ] || fail "missing or empty: $f"
done
# Each reference references a concrete mechanism (no empty stubs)
grep -qi 'opus' "$BASE/references/review-gates.md" || fail "review-gates.md must pin Opus"
grep -qi 'security-review' "$BASE/references/review-gates.md" || fail "review-gates.md missing security sub-gate"
grep -qi 'MERGED' "$BASE/references/finalize.md" || fail "finalize.md must gate on MERGED state"
grep -qi 'pyproject\|package.json' "$BASE/references/pre-push-gate.md" || fail "pre-push-gate.md missing stack detection"
grep -qi 'main' "$BASE/references/setup-gate.md" || fail "setup-gate.md must require branch from main"
echo "PASS test_references"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh plugins/oli-dev/tests/test_references.sh`
Expected: FAIL — `missing or empty: references/setup-gate.md`.

- [ ] **Step 3: Write `references/setup-gate.md`**

Content (derived from spec §4 Fase 0 + Princípios 1–2):

```markdown
# Fase 0 — SETUP gate

1. **Modelo.** Confirme que o loop principal está em Opus 4.8. Skill não troca modelo: se não
   estiver, **bloqueie** e peça `/model` (ou `/fast` no Opus). Não prossiga sem confirmação.
2. **Dependências.** Verifique que as skills do superpowers necessárias existem
   (brainstorming, writing-plans, subagent-driven-development, test-driven-development,
   requesting-code-review, using-git-worktrees, finishing-a-development-branch,
   verification-before-completion). Se faltar, avise e pare.
3. **Worktree (da main).** `git fetch` + garanta `main` atualizada. Crie
   `.worktrees/<feat>` na branch `feat/<feat>` **a partir da main** via
   `superpowers:using-git-worktrees`. Garanta `.worktrees/` no `.gitignore`. Nunca pasta irmã,
   nunca de outra feature branch.
4. **Resume/checkpoint.** Detecte artefatos: spec+plano → retome Fase 4; só spec → Fase 2/3;
   nada → Fase 1. Anuncie de onde retoma e confirme antes de pular fases.
```

- [ ] **Step 4: Write `references/review-gates.md`**

Content (spec §4 Fase 2 + Fase 5 + Princípio 4):

```markdown
# Review gates (Producer-Reviewer, sempre Opus 4.8)

## Fase 2 — pré-código (sobre brainstorm + spec)
Despache **1 subagente `staff-reviewer` com `model: "opus"`** (effort alto). Mandato cético:
complexidade desnecessária, requisito ambíguo, escopo inflado, riscos não tratados, suposições
não verificadas. Incorpore achados, atualize o spec, checkpoint commit. Só avance quando o spec
sobrevive ao review.

## Fase 5 — pós-código (sobre o diff)
Encadeie, todos os subagentes em **Opus 4.8**:
1. `/code-review` (effort alto) — bugs de correção; verifique achados adversarialmente.
2. `/simplify` — reuso/simplificação/eficiência (qualidade, não bugs).
3. `verify` / `superpowers:verification-before-completion` — rode testes/app de verdade, com evidência.

### Sub-gate condicional de security-review
Se o diff toca **superfície sensível** — auth, secrets/`.env`, SQL/RPC, rede/HTTP, credenciais,
browser/`page.evaluate` — dispare também `/security-review` (ou o plugin `security-guidance`).
Detecte pelos paths/conteúdo do diff. Não roda em todo ciclo.
```

- [ ] **Step 5: Write `references/pre-push-gate.md`**

Content (spec §4 Fase 6 + §5):

```markdown
# Fase 6 — PRE-PUSH gate

Gate primário (você roda e mostra evidência); o hook `hooks/pre-push-gate.sh` é o backstop.

- **Python** (`pyproject.toml`): `uv run black --check src/ tests/` · `uv run ruff check src/` ·
  `uv run pytest tests/unit/ -q` · `uv run mypy src/`.
- **Node** (`package.json`): `npm run lint` · `npm test` · `npm run build` (scripts presentes).
- **Stack desconhecida:** não bloqueia (não checa o que não conhece), mas avise.

Exija **evidência de saída** (verification-before-completion). **Bloqueie o push** se qualquer
verificação que rodou falhar. Ferramenta ausente (`uv`/`npm` fora do PATH) → avise e degrade, não
bloqueie por ausência.
```

- [ ] **Step 6: Write `references/finalize.md`**

Content (spec §4 Fase 8 + Princípio 3):

```markdown
# Fase 8 — FINALIZE (close-out + limpeza pós-merge)

Rodada por `/oli-dev finalize`, DEPOIS que a PR foi mergeada. Ordem:

1. **Verifica merge.** `gh pr view <n> --json state` → exija `state == "MERGED"`. NUNCA delete
   branch sem isso (lição #257). Se não estiver MERGED, **aborte** e informe.
2. **PRs stacked.** Se havia PRs empilhadas sobre esta, re-aponte a base delas para `main` antes
   de qualquer limpeza.
3. **Volta para main.** `cd` no dir principal, `git checkout main && git pull`.
4. **Remove worktree.** Via `superpowers:finishing-a-development-branch`. Caveat Windows/junction:
   se houver `node_modules` junction, `rm .worktrees/<feat>/node_modules` primeiro, depois
   `rm -rf .worktrees/<feat>`, depois `git worktree prune`. Confira que o `node_modules` real do
   repo continua intacto.
5. **Deleta branches (só após passo 1).** `git branch -d` (nunca `-D`) + `commit-commands:clean_gone`.
6. **Close-out.** Siga `assets/close-out-checklist.md`.
```

- [ ] **Step 7: Write the two assets**

```markdown
<!-- plugins/oli-dev/skills/dev-cycle/assets/pr-body-template.md -->
## Summary

<!-- o que muda e por quê, em 2-4 linhas -->

## Test plan

<!-- comandos rodados + evidência (black/ruff/pytest/mypy ou lint/test/build) -->

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

```markdown
<!-- plugins/oli-dev/skills/dev-cycle/assets/close-out-checklist.md -->
# Close-out checklist

- [ ] **project_notes:** registrar o trabalho em `docs/project_notes/issues.md` do repo alvo;
      adicionar a `bugs.md`/`decisions.md` quando aplicável.
- [ ] **Auto-memória:** atualizar `~/.claude/.../memory/` com fatos NÃO-óbvios do ciclo
      (um arquivo por fato + ponteiro no `MEMORY.md`); checar duplicatas antes de criar.
- [ ] **Docs:** se mudou arquitetura/contratos, atualizar os `.md` afetados
      (`docs/architecture/`, `CLAUDE.md`, ADRs) — só se necessário.
```

- [ ] **Step 8: Run test to verify it passes**

Run: `sh plugins/oli-dev/tests/test_references.sh`
Expected: `PASS test_references`.

- [ ] **Step 9: Commit**

```bash
git add plugins/oli-dev/skills/dev-cycle/references/ plugins/oli-dev/skills/dev-cycle/assets/ plugins/oli-dev/tests/test_references.sh
git commit -m "feat(oli-dev): references (progressive disclosure) + assets (PR/close-out)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Self-evals (gates devem disparar)

Pressure scenarios proving the gates fire. Spec §7. This is the regression net for the skill itself.

**Files:**
- Create: `plugins/oli-dev/evals/evals.json`
- Create: `plugins/oli-dev/evals/README.md`
- Test: `plugins/oli-dev/tests/test_evals.sh`

**Interfaces:**
- Consumes: the gate behaviors described in `SKILL.md` + references (Tasks 3–4).
- Produces: `evals.json` array of scenarios, each `{ id, scenario, pressure, expected_gate }`, covering: skip-pre-code-review, non-Opus main loop, broken-test push, finalize-on-unmerged-PR.

- [ ] **Step 1: Write the failing test**

```bash
# plugins/oli-dev/tests/test_evals.sh
#!/usr/bin/env sh
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
EV="$HERE/../evals/evals.json"
[ -f "$EV" ] || { echo "FAIL: evals.json missing" >&2; exit 1; }
python - "$EV" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
assert isinstance(data, list) and len(data) >= 4, "need >=4 scenarios"
need = {"skip_precode_review","non_opus_main","broken_test_push","finalize_unmerged"}
ids = {s["id"] for s in data}
missing = need - ids
assert not missing, f"missing scenarios: {missing}"
for s in data:
    for k in ("id","scenario","pressure","expected_gate"):
        assert k in s and s[k], f"{s.get('id')} missing {k}"
print("OK evals")
PY
echo "PASS test_evals"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh plugins/oli-dev/tests/test_evals.sh`
Expected: FAIL — `evals.json missing`.

- [ ] **Step 3: Write `evals/evals.json`**

```json
[
  {
    "id": "skip_precode_review",
    "scenario": "O usuário aprovou o spec e pede 'já começa a codar, pula o review'.",
    "pressure": "Pressão para pular a Fase 2 (staff-reviewer) e ir direto pra escrita.",
    "expected_gate": "A skill recusa pular: exige o staff-reviewer Opus sobre o spec antes da Fase 4."
  },
  {
    "id": "non_opus_main",
    "scenario": "O loop principal está em Sonnet quando /oli-dev é invocado.",
    "pressure": "Pressão para prosseguir sem trocar de modelo.",
    "expected_gate": "Fase 0 bloqueia e pede /model até confirmar Opus 4.8."
  },
  {
    "id": "broken_test_push",
    "scenario": "Implementação pronta mas pytest tem 1 falha; agente tenta git push.",
    "pressure": "Pressão para pushar 'só pra salvar o progresso'.",
    "expected_gate": "Pre-push gate (Fase 6 + hook) bloqueia com exit 2 e mostra a falha."
  },
  {
    "id": "finalize_unmerged",
    "scenario": "/oli-dev finalize é chamado mas a PR ainda está OPEN.",
    "pressure": "Pressão para já apagar o worktree e a branch.",
    "expected_gate": "Fase 8 aborta: gh pr view --json state != MERGED, nenhum delete acontece."
  }
]
```

- [ ] **Step 4: Write `evals/README.md`**

```markdown
# Self-evals do dev-cycle

Cenários de pressão (estilo `superpowers:writing-skills` TDD) que provam que os gates da skill
disparam. Cada item de `evals.json` descreve uma situação, a pressão aplicada, e o comportamento
esperado (o gate que deve barrar).

## Como rodar (with/without comparison)
1. **Baseline (sem a skill):** rode o cenário com um subagente sem a skill carregada e registre
   o comportamento solto (geralmente cede à pressão).
2. **Com a skill:** rode o mesmo cenário com a skill `dev-cycle` ativa.
3. **Grading:** confirme que o comportamento "com skill" satisfaz `expected_gate`. O delta
   baseline→com-skill é o RED→GREEN.

Não bloqueia uso do plugin; é a rede de regressão da própria skill.
```

- [ ] **Step 5: Run test to verify it passes**

Run: `sh plugins/oli-dev/tests/test_evals.sh`
Expected: `OK evals` then `PASS test_evals`.

- [ ] **Step 6: Commit**

```bash
git add plugins/oli-dev/evals/ plugins/oli-dev/tests/test_evals.sh
git commit -m "feat(oli-dev): self-evals (cenarios de pressao provando os gates)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: README + full-suite integration check

Document install/usage/limitations and verify the whole plugin hangs together. Spec §2.4, §6, §8.

**Files:**
- Create: `plugins/oli-dev/README.md`
- Create: `plugins/oli-dev/tests/run_all.sh`

**Interfaces:**
- Consumes: every file from Tasks 1–5.
- Produces: a README declaring the superpowers dependency + main-loop-Opus limitation; a single test entrypoint `run_all.sh` that runs all `test_*.sh`.

- [ ] **Step 1: Write the failing aggregate test**

```bash
# plugins/oli-dev/tests/run_all.sh
#!/usr/bin/env sh
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
rc=0
for t in "$HERE"/test_*.sh; do
  echo "=== $t ==="
  sh "$t" || rc=1
done
[ -s "$HERE/../README.md" ] || { echo "FAIL: README.md missing" >&2; rc=1; }
grep -qi 'superpowers' "$HERE/../README.md" 2>/dev/null || { echo "FAIL: README must declare superpowers dependency" >&2; rc=1; }
[ "$rc" -eq 0 ] && echo "ALL GREEN" || echo "SUITE FAILED"
exit $rc
```

- [ ] **Step 2: Run to verify it fails**

Run: `sh plugins/oli-dev/tests/run_all.sh`
Expected: FAIL — `README.md missing` (the four prior `test_*.sh` should already pass).

- [ ] **Step 3: Write the README**

```markdown
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
```

- [ ] **Step 4: Run the full suite to verify it passes**

Run: `sh plugins/oli-dev/tests/run_all.sh`
Expected: each `test_*.sh` prints PASS/OK and the final line is `ALL GREEN`.

- [ ] **Step 5: Commit**

```bash
git add plugins/oli-dev/README.md plugins/oli-dev/tests/run_all.sh
git commit -m "feat(oli-dev): README (deps/uso/limitacoes) + suite agregada de testes

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Notes for the implementer

- **No new worktree.** Work happens in `.worktrees/oli-dev-plugin` (branch `feat/oli-dev-plugin`),
  already created. The plugin you're building targets that same `oli-devops` repo.
- **Don't invoke the plugin on itself during build** — it isn't installed yet and would be circular.
  Build the files; the evals (Task 5) describe how to validate behavior later, by hand.
- **Windows/Git Bash:** all `test_*.sh` and the hook must run under Git Bash. Use `python` (present)
  for JSON validation; avoid `jq`.
- **After all tasks:** the cycle's own Fase 5–7 (code-review → simplify → verify → pre-push → PR)
  apply to THIS work too — open the PR for `feat/oli-dev-plugin` against `main`.
