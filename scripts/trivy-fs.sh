#!/usr/bin/env bash
# Pre-commit hook: Trivy filesystem scan.
# Policy (pre-commit layer): fail on CRITICAL vulns with fix, or CRITICAL misconfig.
# See oli-devops/policies/ENFORCEMENT.md for the full matrix.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

TRIVY_ARGS=(
  "fs"
  "--scanners" "vuln,secret,misconfig"
  "--severity" "CRITICAL"
  "--ignore-unfixed"
  "--exit-code" "1"
  "--no-progress"
)

if has_local_tool trivy; then
  log_info "using local trivy: $(trivy --version 2>/dev/null | head -n1)"
  exec trivy "${TRIVY_ARGS[@]}" .
fi

check_docker || exit 1

log_info "using trivy via docker: aquasec/trivy:${TRIVY_VERSION}"
MSYS_NO_PATHCONV=1 exec docker run --rm \
  -v "$(docker_pwd):/src:ro" \
  -v "oli-devops-trivy-cache:/root/.cache/trivy" \
  "aquasec/trivy:${TRIVY_VERSION}" \
  "${TRIVY_ARGS[@]}" /src
