---
name: git-commit-prompt
description: Generate optimal prompt for atomic git commits with conventional format. Use when preparing commits or cleaning up git history.
argument-hint: [context] [--atomic] [--worktree] [--venv]
disable-model-invocation: true
---

Write an optimal prompt for a Claude Code AI agent requesting it to atomically commit the changes one file at a time.
Use relatively short conventional commits messages.
Do not add multiple authors such as Claude Code in the commit message.
Ensure you provide relevant context such as worktree, virtual environment, etc.
$ARGUMENTS
