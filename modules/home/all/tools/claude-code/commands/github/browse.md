---
argument-hint: [issue-or-pr-number]
description: Open a GitHub issue or PR in browser from conversation context
---

Open a GitHub issue or pull request in the browser using `gh issue view --web` or `gh pr view --web`.

Requirements:
- If user provides $ARGUMENTS (issue or PR number), use that value
- Otherwise, extract the most recently discussed issue or PR number from the conversation context
- Determine the appropriate repository using one of:
  1. Current git repository (if in a git repo): `git remote get-url origin`
  2. If the issue/PR was discussed with a full org/repo reference, use that
  3. Default to `anthropics/claude-code` if the context suggests Claude Code issues
- Use `gh issue view <number> -R <org/repo> --web` for issues
- Use `gh pr view <number> -R <org/repo> --web` for PRs
- If unclear whether it's an issue or PR, try issue first (gh will auto-detect)

Implementation approach:
1. Extract issue/PR number from $ARGUMENTS or conversation context
2. Determine the repository (current repo, or from context, or claude-code default)
3. Execute: `gh issue view <number> -R <org/repo> --web`
4. The `gh` CLI will automatically open the URL in the default browser

Examples:
- `/github:browse 8677` - Opens issue #8677 in the current/contextual repo
- `/github:browse` - Extracts and opens the most recently discussed issue/PR number

Note: The `gh` CLI intelligently handles both issues and PRs with the same command when using `gh issue view`, so we can use that for both types.
