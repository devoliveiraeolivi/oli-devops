# Release Procedure

How to cut a new version of oli-devops.

## Prerequisites

- [ ] Self-test CI is **green** on the commit you're tagging
- [ ] `CHANGELOG.md` has a new section for the version
- [ ] For MAJOR releases: `CHANGELOG.md` has a `## Migration` subsection
- [ ] Tool version bumps (if any) tested locally against fixtures

## Decide the version bump

See [policies/SEMVER.md](../policies/SEMVER.md). If unsure, ask: "can an
existing consumer pin fail after upgrading?" — if yes, MAJOR; if only new
features, MINOR; if only fixes, PATCH.

## Procedure

### 1. Update `CHANGELOG.md`

Edit the `[Unreleased]` section, move its contents under a new `## [vX.Y.Z]`
heading with today's date:

```markdown
## [v1.0.1] - 2026-04-15

### Fixed
- trivy-fs.sh: correct docker volume mount on Windows Git Bash

## [v1.0.0] - 2026-04-10
...
```

### 2. Commit CHANGELOG

```bash
git add CHANGELOG.md
git commit -m "chore(release): prepare v1.0.1"
git push
```

### 3. Wait for self-test to pass on main

```bash
gh run watch -R devoliveiraeolivi/oli-devops
```

All self-test jobs must be green.

### 4. Tag the release

```bash
git tag -a v1.0.1 -m "v1.0.1"
git push origin v1.0.1
```

### 5. Create GitHub release

```bash
gh release create v1.0.1 \
  --title "v1.0.1" \
  --notes-file <(sed -n '/## \[v1.0.1\]/,/## \[/p' CHANGELOG.md | sed '$d')
```

Or manually via the GitHub UI, copying the CHANGELOG section.

### 6. Verify Renovate picks it up

Within ~1 hour, Renovate should open PRs on all consumer repos that pin an
older version. Check:

```bash
# List open PRs across consumer repos
for repo in oli-gateway oli-auth oli-indexer oli-scraper oli-ops; do
  echo "=== $repo ==="
  gh pr list -R "devoliveiraeolivi/$repo" --label "oli-devops"
done
```

If no PRs appear after a few hours, see the "Renovate not picking up"
section in [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## What NOT to do

- Do not force-push tags. Once `v1.0.1` is tagged, it is immutable.
  If there's a bug, tag `v1.0.2` with the fix.
- Do not skip the CHANGELOG. CI rejects releases without it (future hook).
- Do not tag from a branch other than `main`.
- Do not release while self-test is failing.
