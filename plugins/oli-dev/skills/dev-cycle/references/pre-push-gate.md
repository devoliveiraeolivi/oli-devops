# Fase 6 — PRE-PUSH gate

Gate primário (você roda e mostra evidência); o hook `hooks/pre-push-gate.sh` é o backstop.

- **Python** (`pyproject.toml`):
  - Se existe `scripts/check.sh` no repo → rode **`scripts/check.sh --fast`** (fonte
    única que espelha o `ci.yml`). É o mesmo comando do `.githooks/pre-push` do repo.
  - Senão (fallback): `uv run ruff check src/` · `uv run ruff format --check src/ tests/` ·
    `uv run mypy src/` (baseline-aware: se há `.mypy-baseline.txt`, filtra pelo baseline,
    igual ao CI). **Sem `black`** (legado → `ruff format`) e **sem `pytest`** (os testes já
    rodaram no `verify` da Fase 5).
- **Node** (`package.json`): `npm run lint` · `npm test` · `npm run build` (scripts presentes).
- **Stack desconhecida:** não bloqueia (não checa o que não conhece), mas avise.

Exija **evidência de saída** (verification-before-completion). **Bloqueie o push** se qualquer
verificação que rodou falhar. Ferramenta ausente (`uv`/`npm` fora do PATH) → avise e degrade, não
bloqueie por ausência.

Como o gate já rodou aqui, o push da Fase 7 leva o prefixo `OLI_DEV_GATE_OK=1 git push …` para que o
hook backstop não re-rode a suíte (evita execução dupla). Pushes manuais fora do ciclo não têm o
marcador, então o hook protege normalmente.
