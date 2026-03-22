---
name: git-commit-prompt
description: Generate optimal prompt for atomic git commits with conventional format. Use when preparing commits or cleaning up git history.
argument-hint: [context] [--atomic] [--worktree] [--venv]
disable-model-invocation: true
---

Write an optimal prompt for a Claude Code AI agent requesting it to commit changes per the conventions in git-preferences, one file at a time.
Use relatively short conventional commit messages.
Do not add multiple authors such as Claude Code in the commit message.
Ensure you provide relevant context such as working branch, virtual environment, etc.
$ARGUMENTS
