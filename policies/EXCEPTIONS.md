# Exceptions and Suppressions Policy

Consumer repos can suppress specific findings using `.trivyignore` and
`.gitleaksignore` files at the repo root. This document defines the
**mandatory format** for suppression entries.

## Rationale

Blanket suppressions are how security rot starts. Every suppression must:
1. Be **traceable** (who decided, when, why)
2. Have a **review date** (so stale entries are revisited)
3. Be **justifiable** on audit

## Required format

Every entry in `.trivyignore` or `.gitleaksignore` must have an inline
comment with three fields:

```
CVE-ID  # reason: <concrete reason>, review: YYYY-MM-DD (@owner)
```

### Concrete examples

```
# .trivyignore
CVE-2024-12345  # reason: no fix available upstream, mitigated by network isolation. review: 2026-10-01 (@devoliveiraeolivi)
CVE-2023-98765  # reason: false positive for our build (affects Windows only, we ship Linux). review: 2026-07-15 (@devoliveiraeolivi)
```

```
# .gitleaksignore
# Suppress a specific test fixture that uses canonical AWS example keys
tests/fixtures/aws-example.py:12  # reason: canonical AWS docs example (AKIAIOSFODNN7EXAMPLE), intentional. review: 2027-04-08 (@devoliveiraeolivi)
```

### Required fields

| Field | Description | Example |
|---|---|---|
| `reason:` | Concrete justification — not "accepted", not "won't fix" | `no fix upstream, mitigated by X` |
| `review:` | ISO 8601 date when this entry must be re-evaluated | `2026-10-01` |
| `(@owner)` | GitHub username of the person accepting the risk | `(@devoliveiraeolivi)` |

## Review cadence

- **Temporary** (reason suggests "until X fixed"): review date ≤ **90 days** out
- **Permanent** (reason suggests "structural, won't change"): review date ≤ **1 year** out
- **Quarterly repo sweep**: open an issue listing all entries whose `review:`
  date has passed. Do not auto-remove; human must decide.

## What is NOT acceptable

```
# BAD — no comment
CVE-2024-12345

# BAD — vague reason
CVE-2024-12345  # accepted

# BAD — no review date
CVE-2024-12345  # no fix upstream (@devoliveiraeolivi)

# BAD — no owner
CVE-2024-12345  # no fix upstream, review: 2026-10-01
```

A future version of oli-devops will add a `suppression-format-check` hook
that validates this format automatically. For now, it's manual discipline
enforced at PR review time.

## Scope

These files live in each **consumer repo**, not in oli-devops. oli-devops
defines the format; consumers apply it. Do not create `.trivyignore` or
`.gitleaksignore` in oli-devops itself — the self-test fixtures should be
genuinely clean or genuinely dirty, never "dirty but suppressed".
