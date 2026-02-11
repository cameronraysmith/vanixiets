# shellcheck shell=bash
# Hook: Nudge orchestrator to update CLAUDE.md before context compaction
# When context is compacted, remind the orchestrator to capture important
# project state in CLAUDE.md so it survives across sessions.
# PreCompact (sync) -- reads JSON context from stdin.

set -euo pipefail

# Consume stdin (PreCompact provides session context but we only need the repo)
cat > /dev/null

# Check if CLAUDE.md exists in project root
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
[[ -z "$REPO_ROOT" ]] && exit 0

CLAUDE_MD="$REPO_ROOT/CLAUDE.md"
[[ ! -f "$CLAUDE_MD" ]] && exit 0

# Check if Current State section exists and has content
CURRENT_STATE=$(sed -n '/^## Current State/,/^## /p' "$CLAUDE_MD" | grep -v '^## ' | grep -v '^<!--' | grep -v '^-->' | grep -v '^$' | head -5 || true)

if [[ -z "$CURRENT_STATE" ]]; then
  # Current State is empty -- strong nudge
  cat << 'EOF'
CLAUDE.md MAINTENANCE REMINDER:

The "## Current State" section in CLAUDE.md is empty. Before this context is compacted, consider updating it with:
- Active work in progress (bead IDs, what is being built)
- Recent architectural decisions or trade-offs made
- Known issues or blockers discovered
- Key files or patterns identified during investigation

This information will persist across sessions and help future investigations.

Update with: Edit CLAUDE.md -> add content under "## Current State"
EOF
else
  # Current State has content -- gentle reminder
  cat << 'EOF'
Context is being compacted. If significant progress was made this session, consider updating CLAUDE.md:
- "## Current State" for active work and decisions
- "## Project Overview" if project scope became clearer
- "## Tech Stack" if new technologies were discovered
EOF
fi

exit 0
