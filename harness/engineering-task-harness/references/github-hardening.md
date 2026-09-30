# Hardening Git e GitHub

## Divisão de autoridade

- **Hooks do agente (Codex e Claude):** contexto e prevenção de acidentes durante a sessão.
- **Git hooks locais:** feedback rápido antes de commit/push; não são autoridade porque não são distribuídos automaticamente e podem ser ignorados com `--no-verify`.
- **CI:** validação reproduzível do SHA publicado.
- **GitHub rulesets:** bloqueio central de merge, force-push e exclusão.
- **Revisão humana:** autorização factual ou operacional que CI não consegue inferir.

Não configure `core.hooksPath` global como mecanismo central do produto. Se um repositório precisar de hooks Git, versione os scripts no repo e forneça um instalador explícito; replique a regra crítica no CI.

## Ruleset mínimo para `main`

1. Exigir pull request antes do merge.
2. Exigir os checks de CI pelo nome e, quando possível, restringir a origem ao GitHub App esperado.
3. Exigir resolução das conversas.
4. Bloquear force-push e exclusão.
5. Aplicar também a administradores quando o objetivo for eliminar bypass informal.
6. Para equipes com revisão independente, exigir aprovação da mudança mais recente ou descartar aprovações obsoletas.
7. Usar merge queue apenas em branches com alta concorrência; ela não é necessária para todo repo.

Calibre aprovação humana: um repositório mantido por uma única pessoa pode exigir PR com zero revisores e checks obrigatórios; componentes críticos ou com equipe devem exigir ao menos uma revisão independente. Não transforme deploy, canário ou aprovação de dados em sinônimo de merge.

## GitHub Actions

- Declare `permissions` no menor escopo por workflow ou job; prefira `contents: read` como padrão.
- Fixe actions de terceiros em SHA completo e verificado.
- Evite executar código não confiável com `pull_request_target` ou `workflow_run` quando houver secrets ou token gravável.
- Use ambientes e credenciais de curta duração para deploy; mantenha CI de PR sem segredos de produção.
- Dê nomes únicos aos jobs que serão required checks.
- Não aceite apenas o resultado textual do workflow: confira que o check pertence ao SHA atual do PR.

## Encerramento local com GitHub

1. Consulte PRs pelo `headRefName`.
2. Preserve branches com PR aberto.
3. Se o PR foi mergeado e o HEAD é ancestral do base atualizado, marque apenas como candidata.
4. Se o PR foi mergeado por squash/rebase, confirme equivalência do patch e arquivos antes de limpar.
5. Se o PR foi fechado sem merge ou não existe, preserve até decidir descarte explícito.
6. Separe remoção da worktree, exclusão da branch local e exclusão da branch remota; são três mutações distintas.
