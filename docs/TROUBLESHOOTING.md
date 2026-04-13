# Troubleshooting

Common issues and fixes when adopting or running the oli-devops baseline.

## Pre-commit hook issues

### "Docker daemon not running"

```
[oli-devops] Docker daemon not running.
[oli-devops] Start Docker Desktop and try again.
```

**Fix:** Start Docker Desktop. On Windows, check the system tray icon is
green/running. Confirm with `docker info`.

### First run is slow (~30s+)

On first invocation, Trivy downloads the vulnerability database (~150MB).
This is cached in a Docker volume (`oli-devops-trivy-cache`) and subsequent
runs reuse it.

### Windows path translation errors

If you see errors like `docker: Error response from daemon: invalid mount
config`, the path translation between Git Bash and Docker Desktop failed.

**Fix:**
```bash
# Manually set MSYS_NO_PATHCONV for the shell session
export MSYS_NO_PATHCONV=1
pre-commit run --all-files
```

The scripts already set this for docker commands; this workaround is for
running docker manually.

### "pre-commit not found" inside a git commit hook

Your shell's `PATH` during a git hook may not include `pipx`'s bin directory.

**Fix:** ensure `~/.local/bin` (Linux/Mac) or `%USERPROFILE%\.local\bin`
(Windows) is in PATH in your shell startup file, OR install pre-commit via
`uv tool install pre-commit` which usually handles PATH automatically.

### Hook passes locally but fails in CI

CI uses a different layer (`trivy image` vs `trivy fs`) and stricter policy.
A finding in CI that didn't fire locally is usually a HIGH-severity vuln
with fix available that the local pre-commit ignores by policy.

**Fix:** check the matrix in [policies/ENFORCEMENT.md](../policies/ENFORCEMENT.md)
to understand which layer you need to satisfy. You typically can't "fix it
locally first" because the local scan has a different scope.

## Debugging hook behavior

### Run a single hook verbosely

```bash
pre-commit run trivy-fs --verbose --all-files
pre-commit run gitleaks --verbose --all-files
```

### Run the script directly (bypass pre-commit)

```bash
cd /path/to/target/repo
bash /path/to/oli-devops/scripts/trivy-fs.sh
bash /path/to/oli-devops/scripts/gitleaks-protect.sh
```

This skips pre-commit's caching and shows raw output.

### Bypass hook for one commit (emergency only)

```bash
git commit --no-verify -m "..."
```

**Warning:** CI will still catch it on push. `--no-verify` is for unblocking
yourself during an investigation, not for shipping. Fix the root cause.

## Suppression format errors

Currently manual. A future `suppression-format-check` hook will validate.
See [policies/EXCEPTIONS.md](../policies/EXCEPTIONS.md) for the required format.

## "I updated oli-devops but consumer repos aren't picking it up"

Consumer repos pin an **exact** version (`rev: v1.0.0`). Bumps happen via:
1. Tag a new version in oli-devops
2. Renovate opens a PR in each consumer
3. Review and merge

If Renovate isn't opening PRs:
- Confirm the Renovate GitHub App is installed on the target repo
- Check https://app.renovatebot.com/dashboard for the org
- Verify the repo has `renovate.json` committed
