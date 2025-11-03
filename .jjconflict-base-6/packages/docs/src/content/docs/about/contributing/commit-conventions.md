---
title: Commit Conventions
sidebar:
  order: 2
---

This template relies on PR review process rather than pre-commit hooks for commit message validation.

## Required format

```
<type>(<scope>): <subject>
```

**Types:** `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `chore`, `ci`, `build`

**Scopes:** Package names (e.g., `docs`, `sqlrooms-hf-ducklake`)

**Breaking changes:**
- Include `BREAKING CHANGE:` in footer, or
- Use `!` after type: `feat(api)!: remove deprecated endpoint`

## Examples

```bash
feat(docs): add dark mode toggle
fix(docs): handle null values in query results
docs: update installation guide
```

## Rationale

- PR review catches malformed commits before merge
- No pre-commit friction during local development
- Clear documentation in CONTRIBUTING.md
- Semantic-release requires proper format for version bumps

See [contributing guidelines](/about/contributing/) for detailed conventional commit guidelines.
