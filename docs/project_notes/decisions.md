# Decisões de design (transcritas das PRs no close-out)

Cada entrada registra a escolha **e o porquê** (X sobre Y, trade-offs), com contexto fresco da PR.

## PR #17 (2026-07-02) — ponytail no tier light (opcional, fail-open)

- **`full` não desliga o ponytail** (staff-review): não ligar ≠ desligar — escolha global do
  usuário não é sobrescrita pelo ciclo. Eliminou a necessidade de save/restore na Fase 8.
- **`model-tiers.md` não incorpora o ponytail, mas delimita escopo**: o staff-review proibiu a
  menção (fonte única do tier = modelo); o review pós-código provou que a exclusão total deixava
  o princípio "o tier troca apenas o modelo" factualmente falso → parágrafo "modelo, e só modelo"
  com cross-ref à Fase 0, sem citar o plugin. Spec ajustada com a adjudicação registrada.
- **Detecção autocontida** ("/ponytail na lista de skills da sessão; erro = ausente"): a âncora
  "mesmo mecanismo do passo 2" era circular — o passo 2 não define mecanismo.
- **Calibração de cerimônia por tamanho de diff**: `/code-review` em medium (não high) para diff
  docs-only de ~25 linhas, e `/simplify` satisfeito pelos ângulos de limpeza do próprio review —
  precedente de proporcionalidade registrado na PR.
- **Trial validado pelo usuário** (2026-07-02) → integração mantida; premissas técnicas restantes
  viraram follow-up instrumentado em issues.md (alcance nos subagentes; persistência per-session).

## PR #14 (2026-07-02) — oli-dev hooks hardening + poda do condutor

- **Matriz de shells parametriza a invocação INTERNA do hook** (`OLI_DEV_TEST_SHELL` nos helpers
  `gate_rc`/`gate_err`), nunca o arquivo de teste — o staff-review provou que parametrizar o
  arquivo seria matriz-teatro (o hook continuaria sob `/bin/sh`). Anti-teatro em duas camadas:
  **introspecção** (a matriz é decidida por quem consome a env-var — fonte única, sem whitelist) +
  **meta-assert** no `test_manifests.sh` (arquivo com `gate_rc()` sem a var = FAIL, fecha a
  reversão silenciosa de `"${OLI_DEV_TEST_SHELL:-sh}"` → `sh`).
- **shellcheck é trava de regressão, não caça-bug de portabilidade**: verificado empiricamente
  (fixes reproduzidos contra os commits pré-fix) que nenhuma das 3 fugas históricas — BSD/GNU sed
  (`05fb2ef`), `case` com `)` em `$()` (`591e63d`), `python` vs `python3` (`aeb47c7`) — seria
  detectável por shellcheck. O valor real de portabilidade vem do job `plugin-tests` no ubuntu
  (dash como `/bin/sh` + GNU sed), o eixo de ambiente que o macOS local não cobre.
- **Reescrita python3 dos hooks rejeitada por ora** — regra de ouro do repo: adição > modificação
  na superfície de enforcement; o risco de regressão na migração supera o ganho enquanto a
  matriz+CI seguram a classe. Gatilho de reavaliação registrado em `issues.md`.
- **Poda do condutor sob "evidência ou abstenha"**: a premissa do plano de que o caveat
  Windows/junction "vive na skill do superpowers" foi **refutada** no review pós-código (grep nas
  4 versões em cache de `finishing-a-development-branch`: zero menções a junction/windows/
  node_modules) → o caveat foi mantido no `finalize.md` e o backstop "nunca pasta irmã" restaurado
  no `setup-gate.md`. Delegação de mecânica só onde a cobertura downstream é real e verificada.
- **Custos aceitos com medição** (em vez de complexidade para evitá-los): no ubuntu as duas pernas
  da matriz podem coincidir (`/bin/sh` = dash; +2,5s medidos) e o shellcheck roda 2× no CI (job
  próprio + `test_shellcheck.sh` dentro da suíte; +0,2s). Detectar binário idêntico via readlink
  ou condicionar o teste ao CI adicionaria acoplamento por frações de segundo.
