# Versioning Policy

oli-devops follows [Semantic Versioning](https://semver.org/) strictly.

**Format:** `vMAJOR.MINOR.PATCH` (e.g., `v1.0.0`)

## When to bump each

### MAJOR (breaking)

Anything that can make a previously-passing consumer CI fail after the bump:

- Hook removed from `.pre-commit-hooks.yaml`
- Hook ID renamed
- Required input added to a reusable workflow
- Default severity tightened (matrix row changes from warn to fail)
- Script requires a new external dependency (new tool version incompatible with old runners)
- Policy file renamed or moved

**Required for every MAJOR:**
- `CHANGELOG.md` has a `## Migration` section with concrete steps
- Consumers pin exact version and need explicit PR to adopt

### MINOR (additive, backward-compatible)

- New hook added (consumers must opt in to use it)
- New optional input on a reusable workflow (with sensible default)
- Tool version bump that only *adds* detections (never removes)
- New template for a profile
- New policy document

### PATCH (fixes only)

- Bug fix in a script that doesn't change behavior for working cases
- Documentation fix
- Tool version patch bump (Trivy `0.55.1` → `0.55.2`)
- Template fix
- Self-test fixture refresh (stale CVE → new CRITICAL)

## Pinning

**Consumers MUST pin exact versions** (`rev: v1.0.0`, not `rev: v1`).
Renovate propagates bumps via PR — there is no moving tag.

## Release prerequisites

No tag is cut without:
- Green self-test CI on the commit being tagged
- Updated `CHANGELOG.md` with the new version section
- Updated `docs/ADOPTION-STATUS.md` if consumer expectations changed

See [docs/RELEASE.md](../docs/RELEASE.md) for the full release procedure.
