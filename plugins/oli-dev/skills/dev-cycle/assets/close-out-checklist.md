# Close-out checklist

Roda no `finalize` (pós-merge, sessão nova). A **fonte da verdade é o corpo da PR mergeada**
(seções `## Decisões` e `## Pontas soltas / follow-ups`, escritas com contexto fresco na Fase 7).
Comece lendo `gh pr view <n> --json body` e transcreva de lá — não confie na memória da sessão.

- [ ] **O que foi entregue:** registrar o trabalho em `docs/project_notes/issues.md` do repo alvo
      (ticket/PR + 1-2 linhas do que mudou); adicionar a `bugs.md` se corrigiu bug.
- [ ] **Decisões:** transcrever a seção `## Decisões` da PR para `docs/project_notes/decisions.md`
      (ou ADR, se for decisão arquitetural) — a escolha **e o porquê**, não só o quê.
- [ ] **Pontas soltas / follow-ups:** para cada item de `## Pontas soltas` da PR, criar um registro
      **visível e rastreável** — issue no GitHub (`gh issue create`) e/ou linha em `issues.md`.
      Princípio "sem buracos temporários": deferido só vale se ficou rastreável; nada de `# TODO` mudo.
- [ ] **Auto-memória:** atualizar `~/.claude/.../memory/` com fatos NÃO-óbvios do ciclo
      (um arquivo por fato + ponteiro no `MEMORY.md`); checar duplicatas antes de criar.
- [ ] **Docs:** se mudou arquitetura/contratos, atualizar os `.md` afetados
      (`docs/architecture/`, `CLAUDE.md`, ADRs) — só se necessário.
