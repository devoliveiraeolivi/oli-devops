#!/usr/bin/env bash
# Pre-commit hook: Gitleaks scan on staged files.
# Policy (pre-commit + CI): fail on any secret detection.
# Uses `gitleaks git --pre-commit --staged`, which scans only staged changes.
# (`gitleaks protect` is deprecated since 8.19.0 — same engine, legacy CLI.)
# The filename keeps "protect" because it is referenced by
# .pre-commit-hooks.yaml — renaming it would break every consumer pin.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

GITLEAKS_ARGS=(
  "git"
  "--pre-commit"
  "--redact"
  "--staged"
  "--verbose"
)

if has_local_tool gitleaks; then
  # The `git` subcommand needs gitleaks >= 8.19.0; older local binaries
  # fall through to the pinned docker image instead of hard-failing.
  if gitleaks git --help &> /dev/null; then
    log_info "using local gitleaks: $(gitleaks version 2>/dev/null)"
    exec gitleaks "${GITLEAKS_ARGS[@]}"
  fi
  log_warn "local gitleaks ($(gitleaks version 2>/dev/null)) lacks the 'git' subcommand (< 8.19.0); using docker"
fi

check_docker || exit 1

log_info "using gitleaks via docker: ghcr.io/gitleaks/gitleaks:v${GITLEAKS_VERSION}"
# tag@digest: docker resolves by the (immutable) digest; the tag is
# documentation. See common.sh for why images are digest-pinned.
MSYS_NO_PATHCONV=1 exec docker run --rm \
  -v "$(docker_pwd):/repo:ro" \
  -w /repo \
  "ghcr.io/gitleaks/gitleaks:v${GITLEAKS_VERSION}@${GITLEAKS_IMAGE_DIGEST}" \
  "${GITLEAKS_ARGS[@]}"
