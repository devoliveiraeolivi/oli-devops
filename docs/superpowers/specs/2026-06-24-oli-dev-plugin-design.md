# Design — Plugin `oli-dev`: maestro do ciclo de desenvolvimento

**Data:** 2026-06-24
**Repo alvo:** `oli-devops` (plugin instalável via marketplace próprio)
**Status:** spec aprovado em brainstorming, aguardando review do usuário

---

## 1. Problema e objetivo

Hoje o ciclo de desenvolvimento no ecossistema OLI é executado "à mão": cada fase
(brainstorm, spec, plano, escrita, review, push/PR, limpeza) depende de lembrar de
invocar a skill certa do superpowers, com as configurações certas, na ordem certa.
Faltam **gates opinativos** que o usuário quer fixos em todo ciclo:

- **worktree sempre** (regra do CLAUDE.md global — nunca trabalhar direto numa branch no dir principal);
- **modelo mais forte sempre** (Opus 4.8, thinking, effort max) — pelo menos nos subagentes;
- **um review cético do brain+spec ANTES de escrever código**;
- **um pipeline de review da escrita** (code-review → simplify → verify) antes do push;
- **gate de pré-push obrigatório** (lint/format/test/typecheck) que bloqueia push quebrado;
- **close-out disciplinado** (log institucional + memória + docs) e **limpeza pós-merge** (apagar worktree + branch só depois da PR mergeada).

**Objetivo:** um plugin fino — `oli-dev` — que **conduz** essas fases encadeando as skills
existentes do superpowers e os comandos do ecossistema, com os gates acima embutidos.
Não reimplementa o superpowers; é a **camada opinativa** por cima dele.

### Não-objetivos (YAGNI)

- Não reescrever brainstorming / writing-plans / TDD / code-review — são invocados, não substituídos.
- Não criar agents customizados novos quando os existentes (`staff-reviewer`, `code-reviewer`)
  resolvem com `model: "opus"` passado na chamada.
- Não suportar runtimes além do Claude Code nesta versão (Codex/Gemini ficam para depois).
- Não automatizar o merge da PR (merge continua decisão humana no GitHub).

---

## 2. Forma e empacotamento

### 2.1 Por que plugin (e não skill solto)

A "teia de .md" do Claude Code tem papéis distintos:

| Arquivo | Papel |
|---|---|
| `commands/<x>.md` | **entrada** — o slash command que dispara |
| `skills/<x>/SKILL.md` | **a cola/maestro** — orquestra fases e gates |
| `agents/<x>.md` | definições de **subagentes** (opcional; reusamos os existentes) |
| `hooks/` | **enforcement determinístico** (gate pré-push) |
| `.claude-plugin/plugin.json` | **manifesto** que amarra tudo |

Como o ciclo precisa de **command + skill + hook** bundlados, o container correto é um
**plugin**. Um skill solto em `~/.claude/skills/` não carrega command/hook próprios.

### 2.2 Onde mora

Dentro do **`oli-devops`** — repo central de tooling/CI/security-baseline, cross-repo e
versionado. Ganha distribuição para outras máquinas/repos via marketplace.

### 2.3 Estrutura de arquivos

```
oli-devops/
├─ .claude-plugin/
│  └─ marketplace.json              # registra o marketplace local (1 plugin: oli-dev)
└─ plugins/
   └─ oli-dev/
      ├─ .claude-plugin/plugin.json # manifesto (name, version, description, author)
      ├─ commands/
      │  └─ oli-dev.md              # entrada: /oli-dev <ideia>  e  /oli-dev finalize
      ├─ skills/
      │  └─ dev-cycle/
      │     ├─ SKILL.md             # a COLA / maestro — MAGRA: só o fluxo das 8 fases + 4 seções fixas
      │     ├─ references/          # detalhe carregado sob demanda (progressive disclosure)
      │     │  ├─ setup-gate.md     # checagem de modelo + worktree + deps
      │     │  ├─ review-gates.md   # staff-reviewer pré + code-review/simplify/verify pós + security sub-gate
      │     │  ├─ pre-push-gate.md  # detecção de stack + comandos por linguagem
      │     │  └─ finalize.md       # checklist de close-out + limpeza pós-merge
      │     └─ assets/
      │        ├─ pr-body-template.md     # ## Summary / ## Test plan
      │        └─ close-out-checklist.md  # project_notes + memória + docs
      ├─ hooks/
      │  ├─ hooks.json              # PreToolUse em git push → chama pre-push-gate.sh
      │  └─ pre-push-gate.sh        # auto-detecta stack e roda lint/format/test/typecheck
      ├─ scripts/
      │  └─ model-check.sh          # helper opcional do SETUP gate
      ├─ evals/
      │  ├─ evals.json              # cenários de pressão (gates devem disparar)
      │  └─ README.md               # como rodar with/without comparison
      └─ README.md                  # uso, dependência de superpowers, instalação
```

**Progressive disclosure (inspirado em `revfactory/harness` e na anatomia das skills da
agentskills.io):** a `SKILL.md` é **magra** — contém só o grafo das 8 fases e segue um corpo de
4 seções fixas (**When to Use / Prerequisites / Workflow / Verification**). O detalhe operacional
de cada gate vive em `references/*.md`, lido **sob demanda** quando a fase começa. Isso mantém o
custo de token do maestro baixo em todo ciclo e facilita editar um gate sem mexer no fluxo.

### 2.4 Dependência

O plugin **depende do superpowers** estar instalado (invoca suas skills). O README declara
isso e a SKILL.md, no SETUP gate, verifica a presença das skills-chave e avisa se faltarem.

---

## 3. Disparo (command)

Um único command com dois modos, detectados pelo argumento:

- **`/oli-dev <ideia da feature>`** → roda o ciclo completo da fase 0 até a PR aberta (fases 0–7).
- **`/oli-dev finalize`** → roda só a fase de close-out + limpeza pós-merge (fase 8),
  para ser chamada **depois** que a PR foi mergeada no GitHub.

O command é fino: valida o argumento e invoca a skill `dev-cycle` passando o modo. Toda a
lógica vive na SKILL.md (a cola).

**Resume/checkpoint:** ao iniciar o modo `<ideia>`, o SETUP gate **detecta artefatos já
existentes** no worktree e retoma do ponto certo em vez de recomeçar do brainstorm:

| Artefato presente | Retoma a partir de |
|---|---|
| spec em `docs/superpowers/specs/` + plano em `docs/superpowers/plans/` | Fase 4 (escrita) |
| só o spec | Fase 2 (review pré-código) / Fase 3 (plano) |
| nada | Fase 1 (brainstorm) |

A skill **anuncia** de onde está retomando e pede confirmação antes de pular fases (evita assumir
que um spec velho está aprovado). Isso torna o ciclo resiliente a interrupções.

---

## 4. Pipeline do maestro (SKILL.md `dev-cycle`)

A skill mantém uma checklist (um todo por fase). Modo `<ideia>` executa fases 0–7; modo
`finalize` executa fase 8.

### Princípios de processo (lições de sessões anteriores — invioláveis)

Estes princípios são **gates duros** que atravessam todas as fases. Vêm de erros reais já cometidos:

1. **Uma branch por ciclo, sempre saindo da `main` atualizada.** **Sem PRs stacked por padrão.**
   (Aprendido com o PR #254, que caiu dentro de `fix` por ser stacked.) Se o stacking for
   inevitável, vale a regra de re-apontar a base — mas o **default é uma branch da main**.
2. **Worktree sempre, criado a partir da `main`** (nunca do dir principal numa branch, nunca de
   outra feature branch).
3. **Nunca deletar branch sem `gh pr view <n> --json state`** confirmando `MERGED`.
   (Aprendido com a branch do #257, deletada com a PR ainda aberta — precisou recovery via `refs/pull`.)
4. **Todo review roda no Opus 4.8** — staff-reviewer (Fase 2), code-review/simplify/security
   (Fase 5): subagentes sempre com `model: "opus"`, effort alto. Sem exceção.

### Fase 0 — SETUP gate

1. **Modelo:** verifica se o loop principal está em Opus 4.8. Como skill é markdown e não troca
   o modelo da sessão, se não estiver em Opus 4.8 a skill **bloqueia** e instrui o usuário a
   rodar `/model` (ou `/fast` no Opus). Não prossegue sem confirmação.
2. **Dependências:** confirma que as skills do superpowers necessárias estão disponíveis.
3. **Worktree:** via `superpowers:using-git-worktrees`, primeiro `git fetch` + garante `main`
   atualizada, então cria `.worktrees/<feat>` **dentro do repo alvo**, em branch `feat/<feat>`
   **criada a partir da `main`** (nunca pasta irmã; nunca de outra feature branch; garante
   `.worktrees/` no `.gitignore`). Todo o trabalho subsequente acontece nesse worktree.

### Fase 1 — BRAINSTORM

Invoca `superpowers:brainstorming`. Produz o spec em
`docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md` e o commita (checkpoint).

### Fase 2 — REVIEW GATE (pré-código)

Despacha **um subagente `staff-reviewer` com `model: "opus"`** (effort max) sobre brainstorm+spec.
Mandato cético: complexidade desnecessária, requisito ambíguo, escopo inflado, riscos não tratados,
suposições não verificadas. O maestro resolve/incorpora achados, atualiza o spec, **checkpoint commit**.
Gate: só avança quando o spec sobrevive ao review.

### Fase 3 — PLANO

Invoca `superpowers:writing-plans` para gerar o plano de implementação a partir do spec.
Commit do plano (checkpoint).

### Fase 4 — ESCRITA

Invoca `superpowers:subagent-driven-development`: executa o plano tarefa-a-tarefa, cada tarefa
delegada a um subagente **Opus** seguindo `superpowers:test-driven-development` (RED-GREEN-REFACTOR).
**Checkpoint commit por fase/tarefa concluída** — pontos de retorno limpos no worktree.

**Serial vs paralelo (padrões nomeados, inspirado no catálogo do `revfactory/harness`):** o maestro
escolhe o padrão pela topologia do plano — **Pipeline** (sequencial) quando tarefas têm dependência;
**Fan-out/Fan-in** (`superpowers:dispatching-parallel-agents`) quando há 2+ tarefas independentes sem
estado compartilhado. Isola conflitos de escrita com worktrees por subagente quando paraleliza.

### Fase 5 — REVIEW GATE (pós-código)

Encadeia, em ordem, cada um com propósito distinto (todos os subagentes de review em **Opus 4.8**,
Princípio 4):

1. **`/code-review`** (effort alto) — bugs de correção. Achados verificados adversarialmente.
2. **`/simplify`** — reuso, simplificação, eficiência, altitude (qualidade, não bugs).
3. **`verify` / `superpowers:verification-before-completion`** — roda o app/testes de verdade e
   confirma comportamento com **evidência** (nunca alegar "passa" sem output).

**Sub-gate condicional de security-review (Producer-Reviewer):** se o diff tocar **superfície
sensível** — `auth`, secrets/`.env`, SQL/RPC, rede/HTTP, credenciais, browser/`page.evaluate` —
dispara também `/security-review` (ou o plugin `security-guidance`) além do code-review. Condicional
(não roda em todo ciclo), detectado pelos paths/conteúdo do diff. Encaixa no `security-baseline` do
oli-devops. Os review gates são, no vocabulário do harness, loops **Producer-Reviewer** explícitos.

Itera sobre achados materiais antes de seguir.

### Fase 6 — PRE-PUSH GATE

Roda o gate de pré-push (mesmo que o hook backstop, ver §5):

- **Python** (`pyproject.toml`): `black --check`, `ruff check`, `pytest tests/unit/`, `mypy src/`.
- **Node** (`package.json`): `lint`, `test`, `build` (scripts presentes).

Exige **evidência de saída** (verification-before-completion). **Bloqueia** se qualquer um falhar.

### Fase 7 — PUSH + PR

Invoca `commit-commands:commit-push-pr`. Título curto (<70), corpo com `## Summary` e `## Test plan`.
**Base = `main` (default inviolável):** a PR sai contra `main` — uma branch por ciclo, sem stacking
(Princípio 1). Se o usuário **explicitamente** exigir uma PR stacked, a skill avisa do risco e
registra no corpo da PR a nota de "re-apontar a base para `main` antes de mergear a anterior"
(regra do CLAUDE.md global) — mas isso é exceção, não o caminho normal.
O ciclo `<ideia>` **termina aqui** — em "PR aberta". Não trava esperando merge humano.

### Fase 8 — CLOSE-OUT + limpeza pós-merge (`/oli-dev finalize`)

Invocação separada, rodada **depois** que a PR foi mergeada. Ordem:

1. **Verifica merge:** `gh pr view <n> --json state` → exige `state == "MERGED"`.
   **NUNCA deleta branch sem checar o estado** (lição registrada na memória — deletar branch de
   PR aberta já causou recovery via `refs/pull`). Se não estiver MERGED, aborta e informa.
2. **PR stacked:** se havia PRs empilhadas sobre esta, re-aponta a base delas para `main`
   (ou avisa) antes de qualquer limpeza.
3. **Volta para main:** `cd` no dir principal do repo, `git checkout main && git pull`.
4. **Remove worktree:** via `superpowers:finishing-a-development-branch` (detecção de procedência).
   **Caveat Windows/junction:** se o worktree tiver `node_modules` como junction, `git worktree remove`
   pode falhar com "Invalid argument" — nesse caso remover o link primeiro (`rm .worktrees/<feat>/node_modules`),
   depois `rm -rf .worktrees/<feat>`, e `git worktree prune`. Conferir que o `node_modules` real do repo
   continua intacto (regra do CLAUDE.md global).
5. **Deleta branches (só após o check do passo 1):** nunca deletar sem o `gh pr view --json state ==
   MERGED` (Princípio 3). Branch local mergeada via `git branch -d` (nunca `-D` forçado) +
   `commit-commands:clean_gone` para limpar branches `[gone]` (já deletadas no remote pós-merge).
6. **Log institucional:** registra o trabalho em `docs/project_notes/issues.md` do repo alvo;
   adiciona a `bugs.md`/`decisions.md` quando aplicável (sistema de memória institucional do projeto).
7. **Auto-memória:** atualiza a memória do Claude (`~/.claude/.../memory/`) com fatos **não-óbvios**
   do ciclo, seguindo as regras de memória (um arquivo por fato + ponteiro no MEMORY.md).
8. **Docs:** se o ciclo mudou arquitetura/contratos, atualiza os `.md` afetados
   (`docs/architecture/`, `CLAUDE.md`, ADRs) — só se necessário.

---

## 5. Hook de pré-push (backstop determinístico)

`hooks/hooks.json` registra um **PreToolUse** que casa em comandos `Bash` contendo `git push` e
invoca `pre-push-gate.sh`. O script:

1. **Detecta a stack** pelo diretório do repo: `pyproject.toml` → Python; `package.json` → Node.
2. Roda o gate correspondente (mesmos comandos da Fase 6).
3. **Exit 2** (bloqueia o push) se qualquer verificação falhar, imprimindo o que quebrou no stderr
   (o stderr de um hook PreToolUse com exit≠0 volta como feedback pro agente).
4. **Exit 0** se passar ou se a stack não for reconhecida (não bloqueia o que não sabe checar).

**Ressalvas Windows:** o script roda em Git Bash (POSIX) — usar `command -v` para checar
ferramentas, caminhos POSIX, e degradar com aviso se `uv`/`npm` não estiverem no PATH (não bloquear
por ferramenta ausente, só por verificação que rodou e falhou). Relação skill↔hook: a Fase 6 é o
gate **primário** (o agente roda e mostra evidência); o hook é **backstop** (pega push manual fora
do ciclo). Os dois compartilham a mesma lógica de detecção.

---

## 6. Modelo / pinning

- **Subagentes:** toda chamada de subagente do maestro (staff-reviewer, code-reviewer, executores
  TDD) passa `model: "opus"` (e effort alto onde a chamada permite). Garantido pela skill.
- **Loop principal:** não controlável por skill. Tratado pelo SETUP gate (verifica + bloqueia até
  o usuário confirmar Opus 4.8). Documentado como limitação no README.

---

## 7. Self-evals da skill (testar a própria cola)

Inspirado na *comparative validation* do `revfactory/harness` e no padrão `evals/` da agentskills.io
+ método TDD do `superpowers:writing-skills`: a skill **prova que seus gates disparam**.

- `evals/evals.json` define **cenários de pressão** com asserções, ex.:
  - agente tenta pular o review pré-código → a skill **deve barrar** e exigir o staff-reviewer;
  - loop principal não está em Opus → SETUP gate **deve bloquear**;
  - push com teste quebrado → pre-push gate **deve impedir** (exit 2);
  - `/oli-dev finalize` em PR não-mergeada → **deve abortar**.
- Cada cenário roda em subagente isolado (contexto limpo); grading compara saída vs asserção.
- **With/without comparison:** baseline sem a skill (comportamento solto) vs com a skill (gates ativos),
  documentando o delta — é o RED→GREEN do writing-skills aplicado a esta skill.
- `evals/README.md` explica como rodar. Não bloqueia uso; é a rede de regressão da própria skill.

---

## 8. Critérios de sucesso

1. `/plugin marketplace add` no oli-devops + `/plugin install oli-dev` funcionam; `/oli-dev` aparece.
2. `/oli-dev <ideia>` conduz fases 0–7 sem o usuário precisar invocar skills manualmente, criando
   worktree, passando pelos dois review gates, e terminando em PR aberta.
3. Push com lint/test quebrado é **bloqueado** pelo hook (testado com falha proposital).
4. `/oli-dev finalize` numa PR não-mergeada **aborta**; numa PR mergeada limpa worktree+branch e
   roda o close-out.
5. Subagentes confirmadamente em Opus (verificável no log/telemetria).
6. README documenta dependência de superpowers e a limitação de pinning do loop principal.
7. `/oli-dev <ideia>` com spec+plano já presentes **retoma da Fase 4** (não refaz brainstorm).
8. `evals/evals.json` roda e os cenários de gate passam (gates comprovadamente disparam).

---

## 9. Riscos e mitigação

| Risco | Mitigação |
|---|---|
| Hook de pré-push frágil no Windows | Degrada com aviso se ferramenta ausente; só bloqueia em falha real; testar em Git Bash |
| Superpowers ausente/versão diferente | SETUP gate checa skills-chave e avisa; README fixa dependência |
| Skill não consegue forçar Opus no loop principal | SETUP gate bloqueia até confirmação; subagentes garantidamente Opus |
| `finalize` apagar trabalho não-mergeado | Gate `gh pr view --json state == MERGED` obrigatório antes de qualquer delete |
| Plugin marketplace inédito no oli-devops | Fase de implementação cria `marketplace.json` do zero + README de instalação |

---

## 10. Decisões registradas (do brainstorming)

- Pinning de modelo: **subagentes Opus + checagem de gate no SETUP**.
- Review pré-código: **1 staff-reviewer cético** (Opus).
- Review pós-código: **code-review → simplify → verify**.
- Execução da escrita: **plano + subagent-driven + TDD**.
- Harness extras: **pre-push obrigatório, log em project_notes, update de memória, checkpoint
  commits por fase, update de docs se necessário**.
- Casa: **dentro do oli-devops**. Disparo: **command `/oli-dev <ideia>`**. Hook: **skill + backstop já**.
- Close-out: **subcomando `/oli-dev finalize`** (não trava esperando merge humano).
- Ideias externas incorporadas (garimpo de `revfactory/harness` + `mukul975/...Cybersecurity-Skills`):
  **progressive disclosure** (SKILL.md magra + `references/`/`assets/`), **self-evals** (`evals/`),
  **sub-gate de security-review condicional**, **resume/checkpoint do ciclo**. Padrões nomeados
  (Pipeline / Fan-out / Producer-Reviewer) e corpo de 4 seções (When to Use / Prerequisites /
  Workflow / Verification). **Não importados:** o motor meta-factory do harness (gerar times por
  domínio) e o mapeamento de frameworks de segurança — fora do escopo.
