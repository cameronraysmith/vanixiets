#!/usr/bin/env bash
# Get Claude Code session working directory and metadata
set -euo pipefail

case "${1:-}" in
  -h|--help)
    cat <<'HELP'
Get Claude Code session working directory and metadata

Usage: claude-session-cwd SESSION_ID

Displays the working directory and metadata for a Claude Code session.

Arguments:
  SESSION_ID    UUID of the Claude Code session to query

Output:
  - Session ID
  - Working directory (cwd)
  - Git branch (if applicable)
  - Session file path

Examples:
  claude-session-cwd a2d00721-39cb-49d9-8827-099d0e9f5d38
HELP
    exit 0
    ;;
  "")
    echo "Error: Session ID required" >&2
    echo "Usage: claude-session-cwd SESSION_ID" >&2
    echo "Try 'claude-session-cwd --help' for more information." >&2
    exit 1
    ;;
esac

session_id="$1"
user_home="${HOME:-${HM_HOME_DIR}}"
projects_dir="$user_home/.claude/projects"

# Find the session file
session_file=$(find "$projects_dir" -name "${session_id}.jsonl" -type f 2>/dev/null | head -1)

if [ -z "$session_file" ]; then
  echo "Error: Session not found: $session_id" >&2
  exit 1
fi

# Extract metadata
cwd=$(grep -m1 '"cwd"' "$session_file" | grep -o '"cwd":"[^"]*"' | cut -d'"' -f4)
git_branch=$(grep -m1 '"gitBranch"' "$session_file" | grep -o '"gitBranch":"[^"]*"' | cut -d'"' -f4)

if [ -z "$git_branch" ] || [ "$git_branch" = "null" ]; then
  git_branch="N/A"
fi

# Display results
echo "Session ID: $session_id"
echo "Directory:  $cwd"
echo "Git Branch: $git_branch"
echo "File:       $session_file"
