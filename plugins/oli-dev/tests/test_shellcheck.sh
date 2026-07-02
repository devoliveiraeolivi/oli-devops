#!/usr/bin/env sh
# Trava de regressão de estilo/armadilha nos scripts do plugin. NÃO é caça-bug de
# portabilidade (nenhuma das 3 fugas históricas era detectável por shellcheck — análise na spec
# docs/superpowers/specs/2026-07-02-oli-dev-hooks-hardening-conductor-prune-design.md) — o
# eixo de portabilidade é a matriz de shells + o job plugin-tests do CI.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
if ! command -v shellcheck >/dev/null 2>&1; then
  echo "SKIP: shellcheck ausente — lint não checado localmente (o CI roda sempre)."
  echo "PASS test_shellcheck (skipped)"
  exit 0
fi
shellcheck "$HERE"/../hooks/*.sh "$HERE"/*.sh
echo "PASS test_shellcheck"
