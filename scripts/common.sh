#!/usr/bin/env bash
# Shared utilities for oli-devops pre-commit hooks.
# Sourced by trivy-fs.sh and gitleaks-protect.sh.

set -euo pipefail

# Include guard — prevent double-source errors from readonly re-assignment.
if [[ -n "${__OLI_DEVOPS_COMMON_SH_LOADED:-}" ]]; then
  return 0
fi
readonly __OLI_DEVOPS_COMMON_SH_LOADED=1

# ----- Tool versions (single source of truth) -----
# Bumped in MINOR/PATCH releases per policies/SEMVER.md; procedure in
# CLAUDE.md § "Bumping a tool version".
#
# Images are pinned by multi-arch manifest digest in addition to the tag:
# registry tags are mutable, and the 2026-03 trivy incident shipped malicious
# images under new tags (0.69.5/0.69.6). Refresh digests on every bump:
#   trivy:    curl -s https://hub.docker.com/v2/repositories/aquasec/trivy/tags/<ver> | jq -r .digest
#   gitleaks: TOKEN=$(curl -s "https://ghcr.io/token?scope=repository:gitleaks/gitleaks:pull" | jq -r .token)
#             curl -sI -H "Authorization: Bearer $TOKEN" \
#               -H "Accept: application/vnd.oci.image.index.v1+json" \
#               https://ghcr.io/v2/gitleaks/gitleaks/manifests/v<ver> | grep -i docker-content-digest
# shellcheck disable=SC2034  # referenced by sourcing scripts (trivy-fs.sh, gitleaks-protect.sh)
readonly TRIVY_VERSION="0.72.0"
# shellcheck disable=SC2034  # referenced by sourcing scripts
readonly TRIVY_IMAGE_DIGEST="sha256:cffe3f5161a47a6823fbd23d985795b3ed72a4c806da4c4df16266c02accdd6f"
# shellcheck disable=SC2034  # referenced by sourcing scripts
readonly GITLEAKS_VERSION="8.30.1"
# shellcheck disable=SC2034  # referenced by sourcing scripts
readonly GITLEAKS_IMAGE_DIGEST="sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f"

# ----- Colors -----
# Check stderr (fd 2) because log functions write to stderr.
if [[ -t 2 ]]; then
  readonly RED=$'\033[0;31m'
  readonly GREEN=$'\033[0;32m'
  readonly YELLOW=$'\033[1;33m'
  readonly NC=$'\033[0m'
else
  readonly RED=''
  readonly GREEN=''
  readonly YELLOW=''
  readonly NC=''
fi

log_info() {
  printf '%s[oli-devops]%s %s\n' "$GREEN" "$NC" "$*" >&2
}

log_warn() {
  printf '%s[oli-devops]%s %s\n' "$YELLOW" "$NC" "$*" >&2
}

log_error() {
  printf '%s[oli-devops]%s %s\n' "$RED" "$NC" "$*" >&2
}

# ----- Docker detection -----
check_docker() {
  if ! command -v docker &> /dev/null; then
    log_error "Docker not installed."
    log_error "Install Docker Desktop, or install the tool binary locally."
    return 1
  fi
  if ! docker info &> /dev/null; then
    log_error "Docker daemon not running."
    log_error "Start Docker Desktop and try again."
    return 1
  fi
  return 0
}

# ----- Local tool detection -----
has_local_tool() {
  command -v "$1" &> /dev/null
}

# ----- Path translation for Docker volume mounts on Windows/Git-Bash -----
# On Git Bash (MSYS2), $PWD looks like /c/Apps/oli-devops but Docker Desktop
# expects C:/Apps/oli-devops. The MSYS_NO_PATHCONV=1 env var prevents auto-
# conversion; we do the conversion ourselves when needed.
docker_pwd() {
  if [[ -n "${MSYSTEM:-}" ]]; then
    # Git Bash / MSYS2 / Cygwin
    pwd -W 2>/dev/null || cygpath -w "$PWD" 2>/dev/null || echo "$PWD"
  else
    echo "$PWD"
  fi
}
