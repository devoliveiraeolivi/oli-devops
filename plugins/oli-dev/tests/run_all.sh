#!/usr/bin/env sh
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
rc=0

# Testes de hook rodam 1x por shell da matriz: OLI_DEV_TEST_SHELL parametriza o interpretador
# com que o HOOK é invocado dentro dos helpers (não o arquivo de teste — isso seria teatro).
# Critério da matriz é INTROSPECÇÃO: um teste entra se INVOCA o hook pela forma parametrizada
# `${OLI_DEV_TEST_SHELL:-sh}` (consumo real — uma mera menção da env-var em comentário/prosa não
# qualifica). Fonte única: sem whitelist paralela a apodrecer. O meta-assert em test_manifests.sh
# trava a reversão silenciosa (todo gate_rc() deve invocar pela mesma forma parametrizada).
# Payload principal de portabilidade é o job plugin-tests do CI (ubuntu: dash + GNU sed); a matriz
# local dá feedback rápido. Shell ausente = skip anunciado, nunca silencioso.
SHELLS="sh dash"

for t in "$HERE"/test_*.sh; do
  name="$(basename "$t")"
  if grep -q 'OLI_DEV_TEST_SHELL:-sh' "$t"; then
    for s in $SHELLS; do
      if command -v "$s" >/dev/null 2>&1; then
        echo "=== $name [hook shell: $s] ==="
        OLI_DEV_TEST_SHELL="$s" sh "$t" || rc=1
      else
        echo "=== $name [hook shell: $s] === SKIP: shell '$s' ausente"
      fi
    done
  else
    echo "=== $name ==="
    sh "$t" || rc=1
  fi
done
[ -s "$HERE/../README.md" ] || { echo "FAIL: README.md missing" >&2; rc=1; }
grep -qi 'superpowers' "$HERE/../README.md" 2>/dev/null || { echo "FAIL: README must declare superpowers dependency" >&2; rc=1; }
[ "$rc" -eq 0 ] && echo "ALL GREEN" || echo "SUITE FAILED"
exit $rc
