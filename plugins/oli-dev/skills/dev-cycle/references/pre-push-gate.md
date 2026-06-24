# Fase 6 — PRE-PUSH gate

Gate primário (você roda e mostra evidência); o hook `hooks/pre-push-gate.sh` é o backstop.

- **Python** (`pyproject.toml`): `uv run black --check src/ tests/` · `uv run ruff check src/` ·
  `uv run pytest tests/unit/ -q` · `uv run mypy src/`.
- **Node** (`package.json`): `npm run lint` · `npm test` · `npm run build` (scripts presentes).
- **Stack desconhecida:** não bloqueia (não checa o que não conhece), mas avise.

Exija **evidência de saída** (verification-before-completion). **Bloqueie o push** se qualquer
verificação que rodou falhar. Ferramenta ausente (`uv`/`npm` fora do PATH) → avise e degrade, não
bloqueie por ausência.

Como o gate já rodou aqui, o push da Fase 7 leva o prefixo `OLI_DEV_GATE_OK=1 git push …` para que o
hook backstop não re-rode a suíte (evita execução dupla). Pushes manuais fora do ciclo não têm o
marcador, então o hook protege normalmente.
