#!/usr/bin/env bash
# Pre-commit hook: Gitleaks scan on staged files.
# Policy (pre-commit + CI): fail on any secret detection.
# Uses `gitleaks protect --staged` which scans only files in git's index.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

GITLEAKS_ARGS=(
  "protect"
  "--staged"
  "--verbose"
  "--redact"
)

if has_local_tool gitleaks; then
  log_info "using local gitleaks: $(gitleaks version 2>/dev/null)"
  exec gitleaks "${GITLEAKS_ARGS[@]}"
fi

check_docker || exit 1

log_info "using gitleaks via docker: ghcr.io/gitleaks/gitleaks:v${GITLEAKS_VERSION}"
MSYS_NO_PATHCONV=1 exec docker run --rm \
  -v "$(docker_pwd):/repo:ro" \
  -w /repo \
  "ghcr.io/gitleaks/gitleaks:v${GITLEAKS_VERSION}" \
  "${GITLEAKS_ARGS[@]}"
