# CLAUDE.md — oli-devops

Instructions for AI assistants (Claude Code, Claude Agent SDK) working in
this repo.

## Purpose

This is the **centralized security baseline** for all OLI repos. Changes
here propagate to ~5 consumer repos (Phase 1) and ~15+ more (Phase 2+).
Every change is high-leverage and every bug is amplified.

## Golden rules

1. **NEVER** tag a release without self-test CI green. No exceptions.
2. **NEVER** modify `policies/ENFORCEMENT.md` without a MAJOR version bump
   and an explicit migration plan.
3. **NEVER** delete or rename a hook ID (`trivy-fs`, `gitleaks`) — breaking
   change for every consumer.
4. **PREFER** adding new hooks to modifying existing ones. Additions are MINOR;
   modifications are MAJOR.
5. **ALWAYS** update `CHANGELOG.md` in the same commit as the feature/fix.
6. **ALWAYS** test locally against fixtures before pushing.

## Key files

| File | Role |
|---|---|
| `.pre-commit-hooks.yaml` | Public contract — hook IDs, never rename |
| `scripts/trivy-fs.sh` | Pre-commit layer of trivy |
| `scripts/gitleaks-protect.sh` | Pre-commit layer of gitleaks |
| `.github/workflows/security.yml` | CI layer (reusable) |
| `.github/workflows/self-test.yml` | Meta-CI — must be green before tag |
| `policies/ENFORCEMENT.md` | The matrix — changing = MAJOR bump |
| `policies/SEMVER.md` | Versioning rules |
| `policies/EXCEPTIONS.md` | Suppression format — consumers follow this |
| `docs/ONBOARDING.md` | Master procedure; skill (Plan 2) reflects this |
| `docs/RELEASE.md` | Release checklist |
| `tests/fixtures/` | Self-test fixtures — keep realistic and current |

## How to make changes

### Adding a new hook

1. Write the script in `scripts/<new-hook>.sh`
2. Add entry in `.pre-commit-hooks.yaml`
3. Add self-test jobs in `.github/workflows/self-test.yml` (clean + dirty fixture)
4. Add fixtures in `tests/fixtures/<clean-case>/` and `tests/fixtures/<dirty-case>/`
5. Update `policies/ENFORCEMENT.md` to document the policy
6. Update `templates/*/pre-commit-config.yaml` to include the new hook
7. Bump **MINOR** version (new hook is opt-in unless templates force it)
8. Update CHANGELOG

### Bumping a tool version

1. Update `TRIVY_VERSION` or `GITLEAKS_VERSION` in `scripts/common.sh`
2. Run self-test locally:
   ```bash
   cd tests/fixtures/clean && bash ../../../scripts/trivy-fs.sh  # should pass
   # etc for each fixture
   ```
3. If behavior unchanged → **PATCH**
4. If new detections (stricter scanner) → **MINOR**
5. If old detections removed (looser) → **MAJOR** (regression risk)
6. Update CHANGELOG with the specific version diff

### Modifying the enforcement matrix

**This is almost always a MAJOR bump.** Ask yourself: could a consumer who
passes today fail after this change? If yes → MAJOR.

1. Update `policies/ENFORCEMENT.md` matrix table AND rationale
2. Update `scripts/trivy-fs.sh` and/or `.github/workflows/security.yml`
3. Add a `## Migration` section in CHANGELOG explaining:
   - What changed
   - Likely new failures for existing consumers
   - How to fix each
   - How to suppress if needed (with proper format)
4. Bump MAJOR
5. Coordinate with consumer repo maintainers before tagging

## Testing locally

```bash
# Test a single script against a fixture
cd tests/fixtures/with-critical-cve
bash ../../../scripts/trivy-fs.sh
echo $?  # should be 1

cd tests/fixtures/clean
bash ../../../scripts/trivy-fs.sh
echo $?  # should be 0
```

For gitleaks, set up a temp git repo first (see `self-test.yml` for exact
commands).

## Releasing

See [docs/RELEASE.md](docs/RELEASE.md). In short:

```bash
# After self-test green and CHANGELOG updated:
git tag -a v1.0.1 -m "v1.0.1"
git push origin v1.0.1
gh release create v1.0.1 --notes-file <(sed -n '/## \[v1.0.1\]/,/## \[/p' CHANGELOG.md | sed '$d')
```

## Phase 2 anticipated work

- New profile: `docker-only` (no pyproject, no package.json)
- New profile: `python-only` (no Dockerfile, skip image scan)
- `suppression-format-check` hook (validates `.trivyignore` format)
- SBOM generation (Syft) in reusable workflow
- Dashboard of adoption status

Do not start Phase 2 work without Phase 1 DoD met (see spec section 11).

## Related repos

- Consumers (Phase 1): `oli-gateway`, `oli-auth`, `oli-indexer`, `oli-scraper`, `oli-ops`
- Consumers (Phase 2): see `docs/ADOPTION-STATUS.md`
- Design spec: `devoliveiraeolivi/oli-gateway` at
  `docs/superpowers/specs/2026-04-08-oli-devops-security-baseline-design.md`
