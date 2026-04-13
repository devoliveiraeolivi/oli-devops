## Security Baseline

Este repo adota o baseline de segurança central em
[oli-devops](https://github.com/devoliveiraeolivi/oli-devops)
(pinado em `.pre-commit-config.yaml`, perfil **python-docker**).

- **Hooks ativos (pre-commit)**: `trivy-fs`, `gitleaks`
- **Rodar manualmente**: `pre-commit run --all-files`
- **CI**: job `security-baseline` usa o reusable workflow
  `devoliveiraeolivi/oli-devops/.github/workflows/security.yml@v1.0.0`
- **Suprimir achado**: adicionar em `.trivyignore` ou `.gitleaksignore` com
  formato obrigatório: `CVE-XXXX  # reason: <razão>, review: YYYY-MM-DD (@owner)`
  — ver [EXCEPTIONS policy](https://github.com/devoliveiraeolivi/oli-devops/blob/main/policies/EXCEPTIONS.md)
- **Matriz de enforcement**: ver [ENFORCEMENT policy](https://github.com/devoliveiraeolivi/oli-devops/blob/main/policies/ENFORCEMENT.md)
- **NÃO modifique** o job `security-baseline` localmente — mude em `oli-devops`
  e releasse nova versão. Renovate propaga.
