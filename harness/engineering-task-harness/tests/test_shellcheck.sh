#!/usr/bin/env sh
# Trava de regressão de estilo/armadilha nos hooks shell. NÃO é caça-bug de portabilidade
# (nenhuma das 3 fugas históricas do oli-dev era detectável por shellcheck) — o eixo de
# portabilidade é a matriz de shells + o workflow harness.yml (ubuntu: dash + GNU sed).
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
if ! command -v shellcheck >/dev/null 2>&1; then
  echo "SKIP: shellcheck ausente — lint não checado localmente (o CI roda sempre)."
  echo "PASS test_shellcheck (skipped)"
  exit 0
fi
shellcheck "$HERE"/../scripts/*.sh "$HERE"/*.sh
echo "PASS test_shellcheck"
