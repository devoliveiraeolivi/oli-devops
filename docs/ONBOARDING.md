# Onboarding a Repo to the oli-devops Security Baseline

This is the **canonical procedure** for adopting the baseline in a new repo.
Humans follow this directly; the `adopt-security-baseline` skill (Plan 2)
executes these same steps.

## Prerequisites

### One-time per machine
- [ ] Docker Desktop installed and running
- [ ] `pre-commit` installed: `pipx install pre-commit` (or `uv tool install pre-commit`)
- [ ] `gh` CLI authenticated: `gh auth status`
- [ ] Local clone of `oli-devops` (so templates and skill are available)

### One-time per GitHub org
- [ ] Renovate GitHub App installed: https://github.com/apps/renovate
      Configure it to watch the target repos

### One-time per target repo
- [ ] Repo has a `Dockerfile` at root (or note the path for `dockerfile:` input)
- [ ] Repo has `.github/workflows/ci.yml` (or create one from scratch)
- [ ] Write access confirmed: `gh repo view <owner>/<repo>`

## Procedure

### Step 1 — Detect profile

| Repo contains | Profile |
|---|---|
| `pyproject.toml` + `Dockerfile` | `python-docker` |
| `package.json` + `Dockerfile` | `js-docker` |
| `Dockerfile` only (no language manifest) | `docker-only` (Phase 2+) |
| Neither | **not yet supported** — stop |

### Step 2 — Create adoption branch

```bash
cd /path/to/target/repo
git checkout main
git pull
git checkout -b chore/adopt-security-baseline-v1.0.0
```

### Step 3 — Copy template files

From `oli-devops/templates/<profile>/`:

```bash
OLIDEVOPS=/path/to/oli-devops   # your local clone
PROFILE=python-docker            # or js-docker

# Pre-commit config: CREATE or MERGE
if [ -f .pre-commit-config.yaml ]; then
  echo "Existing .pre-commit-config.yaml — MERGE manually, do not overwrite"
  # Open both files; append the oli-devops repo block to the existing file.
  # Preserve all existing hooks.
else
  cp "$OLIDEVOPS/templates/$PROFILE/pre-commit-config.yaml" .pre-commit-config.yaml
fi

# Renovate config: CREATE or MERGE
if [ -f renovate.json ]; then
  echo "Existing renovate.json — merge packageRules manually"
else
  cp "$OLIDEVOPS/templates/$PROFILE/renovate.json" renovate.json
fi
```

**Replace `REPLACE_WITH_REPO_NAME` in** `templates/$PROFILE/ci-security-job.yml`
(you'll insert this snippet into ci.yml in Step 5 — don't copy the file
directly, copy the job block into the existing ci.yml).

### Step 4 — Install and first scan (the "inheritance tax")

```bash
pre-commit install
pre-commit run --all-files
```

**Expected outcome:** findings from pre-existing issues. This is normal for
the first scan. Triage each finding:

| Decision | Action |
|---|---|
| **Fix now** | Bump dep, remove secret, fix misconfig → re-run |
| **Suppress (permanent)** | Add to `.trivyignore` or `.gitleaksignore` with format from [EXCEPTIONS.md](../policies/EXCEPTIONS.md). Review date ≤ 1 year |
| **Suppress (temporary)** | Same format, review date ≤ 90 days, reason must mention the fix timeline |

Re-run `pre-commit run --all-files` until it passes cleanly.

**Do NOT** suppress without filling all required fields (`reason:`, `review:`,
`@owner`). Entries without the format will fail a future
`suppression-format-check` hook.

### Step 5 — Update ci.yml

Open `.github/workflows/ci.yml` in the target repo.

**If there is an existing `security` job** (ex: inline Trivy scan):
- Remove it entirely.
- Note any non-baseline checks it was doing (like `pip-audit`) — these stay
  as separate jobs, they don't move to oli-devops.

**Add the new job** from `templates/<profile>/ci-security-job.yml`:

```yaml
  security-baseline:
    name: Security Baseline (oli-devops)
    uses: devoliveiraeolivi/oli-devops/.github/workflows/security.yml@v1.0.0
    with:
      image-name: <repo-name>   # e.g., oli-gateway
```

Replace `<repo-name>` with the actual repo name. Position the job after
lint/test, before build-and-push. If the old security job was in `needs:` of
`build-and-push`, update to `needs: [lint, test, security-baseline]`.

### Step 6 — Update CLAUDE.md

Append the contents of `oli-devops/templates/<profile>/claude-md-section.md`
to the target repo's CLAUDE.md under a new `## Security Baseline` section.
If the section already exists, update it to match the template.

### Step 7 — Commit and open PR

```bash
git add .pre-commit-config.yaml renovate.json .github/workflows/ci.yml CLAUDE.md .trivyignore .gitleaksignore 2>/dev/null || true
git commit -m "chore(security): adopt oli-devops baseline v1.0.0"
git push -u origin chore/adopt-security-baseline-v1.0.0
gh pr create \
  --title "chore(security): adopt oli-devops baseline v1.0.0" \
  --body "Onboards this repo to the centralized security baseline. See oli-devops v1.0.0 release notes."
```

### Step 8 — Verify CI

```bash
gh pr checks
```

Wait for all checks to complete. All must be green (or explicitly expected
to warn). If any check fails:

- **security-baseline / trivy-image fails**: findings at HIGH+ with fix in
  image layer. Either fix (bump base image, bump deps) or open issue to
  escalate.
- **security-baseline / gitleaks fails**: a secret in history. If it's a
  test fixture, add to `.gitleaksignore` with justification.
- **pre-commit fails**: re-run locally, fix, re-push.

### Step 9 — Merge

Once green:
```bash
gh pr merge --squash
```

### Step 10 — Post-merge verification

```bash
# Wait a moment for main branch CI to run
gh run list -R <owner>/<repo> --limit 3
```

Verify the `security-baseline` job is green on main.

### Step 11 — Record in ADOPTION-STATUS.md

Update `oli-devops/docs/ADOPTION-STATUS.md` to mark this repo as onboarded
with the version pinned.

## Merging with existing pre-commit config

If the target repo already has `.pre-commit-config.yaml` (example: `oli-scraper`):

1. **Open the existing file.** Identify the existing `repos:` list.
2. **Append** the oli-devops block — do not replace anything:

```yaml
repos:
  # ... existing entries stay as-is ...
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.5.0
    hooks:
      - id: trailing-whitespace
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.6.9
    hooks:
      - id: ruff

  # --- oli-devops security baseline (appended) ---
  - repo: https://github.com/devoliveiraeolivi/oli-devops
    rev: v1.0.0
    hooks:
      - id: trivy-fs
      - id: gitleaks
```

3. **Re-run `pre-commit install`** to install the new hooks.
4. **Re-run `pre-commit run --all-files`** — expect new findings only from
   trivy-fs and gitleaks.

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
