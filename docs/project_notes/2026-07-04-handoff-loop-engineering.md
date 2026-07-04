# Handoff — melhorias derivadas da avaliação do paper "loop engineering"

**Data:** 2026-07-04. **Origem:** avaliação do arXiv 2607.00038 ("Stop Hand-Holding
Your Coding Agent", Sandeco Macedo, cs.SE) contra a skill `dev-cycle` do plugin
oli-dev. Este doc é autocontido — uma sessão futura executa sem precisar da
conversa original.

> **Contexto pós-split (2026-07-04, mesma data):** o plugin `oli-dev` foi extraído
> deste repo para o marketplace [`devoliveiraeolivi/oli-plugins`](https://github.com/devoliveiraeolivi/oli-plugins)
> (PR #20 aqui; release `oli-dev-v1.0.0` lá). `plugins/oli-dev/` **não existe mais
> neste repo** — a Melhoria 2 (promover checklist a reference) e os não-fazer sobre
> a skill `dev-cycle` executam no repo novo. A Melhoria 1 (loop Renovate) segue
> sendo deste repo (é sobre os consumers do baseline).

## Veredicto (contexto, não ação)

O paper propõe *loop specifications* com 5 componentes: **gatilho, objetivo,
verificação, regra de parada e memória**. A skill `dev-cycle` já satisfaz essa
anatomia — verificação com evidência obrigatória, gates duros, estado terminal
explícito (Fases 7/8), resume/checkpoint na Fase 0 — e em verificação está acima
dos 70% do corpus do paper. **Não adotar o framework formalmente; não mudar a
skill por causa do paper.** Ressalva sobre a fonte: autor único, tom de
ensaio/taxonomia, corpus de 50 loops sem benchmark de resultado — vale como
vocabulário, não como fonte de requisitos.

## Melhoria 1 — loop agendado de verificação Renovate/gitleaks-action (P0, prazo real)

O único gap do paper que mapeia numa necessidade concreta do repo: **gatilho
automatizado** para um follow-up datado que hoje depende de memória humana.

**Fatos (verificados 2026-07-04):**

- `v1.2.0` está tageada; o `security.yml` da main carrega
  `gitleaks-action@…e8d1e # v3.0.0` (SHA-pinned) — o baseline já está corrigido.
- Todos os consumers adotados pinam `security.yml@v1.1.1` (gitleaks-action@v2,
  Node 20) → CI quebra em **2026-09-16** quando os runners GitHub-hosted
  descontinuam Node 20.
- O manager `github-actions` do Renovate deveria abrir os bump PRs sozinho
  (atrasados pelo `minimumReleaseAge` de cada repo). **Janela de verificação
  termina ~2026-07-10** — ou seja, primeira execução do loop é AGORA, não
  "quando der". Fonte: `docs/ADOPTION-STATUS.md` § Propagation gaps.
- **`oli-etl` não tem `renovate.json`** (404, verificado 2026-07-04) → nunca terá
  bump automático; a regra de parada (b) se aplica a ele **desde já** — bump
  manual + adicionar `renovate.json` de carona (feito na primeira execução, ver
  memória no `issues.md`).

**Especificação do loop (nos 5 componentes):**

| Componente | Valor |
|---|---|
| Gatilho | **One-shot agendado para 2026-07-09** (pós-`minimumReleaseAge` de 5d sobre a tag de 07-02). Primeira execução já feita em 2026-07-04 (memória no `issues.md`). Recorrência semanal só se a rodada de 07-09 terminar em "aguardando" |
| Objetivo | Todos os consumers adotados com pin `security.yml@ >= v1.2.0` |
| Verificação | Por repo (oli-gateway, oli-auth, oli-scraper, oli-ops, anp-bi-etl, oli-etl): checar o **valor do pin** no workflow (fonte autoritativa) + `gh pr list -R devoliveiraeolivi/<repo> --author "app/renovate"` para bump PRs. **Não** usar `--search "renovate"`: falso-positivo com os 5 PRs de backfill `chore(renovate): habilita o manager pre-commit` (2026-07-02, autor humano), que são da lacuna 2 e não deste loop |
| Regra de parada | (a) todos os pins ≥ v1.2.0 → desligar o loop e atualizar `ADOPTION-STATUS.md`; ou (b) 2026-07-10 sem PRs do Renovate → escalar para bump manual em cada consumer (hard deadline 2026-09-16). Para `oli-etl`, (b) aplicada desde já (sem renovate.json) |
| Memória | Resultado de cada execução anotado no follow-up correspondente em `issues.md` |

**Relacionado, mas fora deste loop:** os pins `rev:` do pre-commit também não
são auto-bumpados em consumers já onboardados (precisam patchar o próprio
`renovate.json` com `"pre-commit": {"enabled": true}`) — já rastreado em
`ADOPTION-STATUS.md` § Propagation gaps, item 2.

## Melhoria 2 — checklist dos 5 componentes para novos loops (custo zero)

Ao criar qualquer automação nova (cron, agente agendado, hook), sanity-check
mental: tem gatilho definido? objetivo? verificação autônoma (não
model-as-judge cru)? regra de parada? onde fica a memória entre execuções?
Sem mudança de skill, sem doc novo — regra-dos-três do repo: se surgir um 3º
loop automatizado no ecossistema, aí sim considerar promover o checklist a
reference do plugin.

## Não-fazer (com gatilho de reavaliação, no padrão do repo)

- **Não** incorporar o vocabulário/framework do paper na skill `dev-cycle`.
- **Não** construir memória persistente entre ciclos do oli-dev — o
  resume/checkpoint da Fase 0 cobre a necessidade real. Gatilho de
  reavaliação: um ciclo real perder contexto que o resume não recupera
  (ex.: re-adjudicar entre ciclos uma decisão já registrada).

## Micro-item (carona, não vale PR própria)

- Comentário defasado em `.github/workflows/security.yml:36` justifica a
  permissão `pull-requests:read` citando `gitleaks-action@v2`, mas a action é
  v3.0.0. Na próxima PR que tocar o arquivo: confirmar se o v3 ainda exige a
  permissão e atualizar o comentário.
