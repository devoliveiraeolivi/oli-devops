#!/usr/bin/env bash
# Shared utilities for oli-devops pre-commit hooks.
# Sourced by trivy-fs.sh and gitleaks-protect.sh.

set -euo pipefail

# ----- Tool versions (single source of truth) -----
# Bumped in MINOR/PATCH releases per policies/SEMVER.md.
# VERIFY current versions before committing — see Task 3 Step 1.
readonly TRIVY_VERSION="0.69.3"
readonly GITLEAKS_VERSION="8.30.1"

# ----- Colors -----
if [[ -t 1 ]]; then
  readonly RED='\033[0;31m'
  readonly GREEN='\033[0;32m'
  readonly YELLOW='\033[1;33m'
  readonly NC='\033[0m'
else
  readonly RED=''
  readonly GREEN=''
  readonly YELLOW=''
  readonly NC=''
fi

log_info() {
  printf "${GREEN}[oli-devops]${NC} %s\n" "$*" >&2
}

log_warn() {
  printf "${YELLOW}[oli-devops]${NC} %s\n" "$*" >&2
}

log_error() {
  printf "${RED}[oli-devops]${NC} %s\n" "$*" >&2
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
