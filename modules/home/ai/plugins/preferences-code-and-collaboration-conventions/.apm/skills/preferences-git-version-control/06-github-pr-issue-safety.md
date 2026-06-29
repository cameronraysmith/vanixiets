# GitHub PR and Issue creation safety

GitHub's immutability policies require careful workflow to avoid permanent unwanted records:

- PR and Issue titles and descriptions cannot be edited after creation
- GitHub will not delete PRs or Issues without proof of sensitive data

Always use placeholder content in immutable fields, then update mutable fields after human review.

## PR creation protocol

Create PRs in draft mode with generic placeholder content:

```sh
gh pr create \
  -d \
  -a "@me" \
  -B main \
  -t "[conventional commits-formatted terse PR title]" \
  -b ""
```

After creation, provide follow-up commands for human review:

- Update PR title using `gh pr edit <number> --title "conventional: commits format"`
- Add actual description as second comment using `gh pr comment <number> --body "markdown description"`
- Never edit the immutable PR description field created at PR creation time
- Wait for user approval before executing

## Issue creation protocol

Apply identical safety patterns to `gh issue create`:

- Create with placeholder title and "empty" body
- Provide follow-up commands for title update and comment-based description
- Never edit the immutable Issue description field

## Cross-reference safety

Include `www` in GitHub URLs to prevent automatic backlinking:

- Use: `https://www.github.com/org/repo/issues/123`
- Avoid: `https://github.com/org/repo/issues/123` (creates immediate backlink)
- User removes `www` after confirming reference is intentional

## Uncertainty protocol

When uncertain about any aspect of PR or Issue creation:

1. Pause execution
2. Present proposed creation command with placeholders
3. Show intended title and description separately
4. Provide follow-up commands for mutable field updates
5. Await user confirmation

This ensures immutable GitHub records stay generic while preserving user control over deletable content.

## See also

- [`SKILL.md`](SKILL.md) — top-level git version control principles, glossary, and routing index
- [`05-commit-workflow.md`](05-commit-workflow.md) — atomic commit workflow operational recipes
