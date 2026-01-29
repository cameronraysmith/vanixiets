---
name: github-browse
description: Open a GitHub issue or PR in browser and optionally manage subscriptions. Use when navigating to GitHub resources from the terminal.
argument-hint: [issue-or-pr-number] [sub|un]
disable-model-invocation: true
---

Open a GitHub issue or pull request in the browser using `gh issue view --web` or `gh pr view --web`.
Optionally subscribe or unsubscribe from notifications for the issue/PR.

Requirements:
- If user provides $1 (issue or PR number), use that value
- Otherwise, extract the most recently discussed issue or PR number from the conversation context
- Determine the appropriate repository using one of:
  1. Current git repository (if in a git repo): `git remote get-url origin`
  2. If the issue/PR was discussed with a full org/repo reference, use that
  3. Default to `anthropics/claude-code` if the context suggests Claude Code issues
- Use `gh issue view <number> -R <org/repo> --web` for issues
- Use `gh pr view <number> -R <org/repo> --web` for PRs
- If unclear whether it's an issue or PR, try issue first (gh will auto-detect)

Subscription management (optional):
- If $2 is "sub", subscribe to notifications for this issue/PR
- If $2 is "un", unsubscribe from notifications for this issue/PR
- If $2 is blank/not provided, do not perform any subscription action
- Subscription requires the `notifications` scope in your gh token
  - If not present, run: `gh auth refresh -h github.com -s notifications`
- Uses GraphQL API to get the issue/PR ID and update subscription state

Implementation approach:
1. Extract issue/PR number from $1 or conversation context
2. Determine the repository (current repo, or from context, or claude-code default)
3. Execute: `gh issue view <number> -R <org/repo> --web`
4. If $2 is "sub" or "un":
   a. Query GraphQL to get the issue/PR's subscribableId
   b. Execute updateSubscription mutation with appropriate state (SUBSCRIBED for "sub", UNSUBSCRIBED for "un")
   c. Handle both issues and PRs (query should check both types)
5. The `gh` CLI will automatically open the URL in the default browser

Examples:
- `/github:browse 8677` - Opens issue #8677 in the current/contextual repo
- `/github:browse 8677 sub` - Opens issue #8677 and subscribes to notifications
- `/github:browse 8677 un` - Opens issue #8677 and unsubscribes from notifications
- `/github:browse` - Extracts and opens the most recently discussed issue/PR number

Note: The `gh` CLI intelligently handles both issues and PRs with the same command when using `gh issue view`, so we can use that for both types.
