# shellcheck shell=bash
# Hook: Verify development-join integrity before edit-class tool operations.
# Tier-aware: only fires when a multi-parent join (description "join N=...") is
# present in mutable() history. Tier 1 (anonymous chain on @) and tier 2 (single
# named bookmark) are no-ops per modules/home/ai/skills/src/core/jj-version-control/tiered-ceremony.md.
# Note: the "join N=k: ..." description prefix is a project convention used in
# this repo's diamond-workflow tooling; see ~/.claude/skills/jj-version-control/SKILL.md.
# Tier 3 (development join present) runs the diamond-health invariant checklist:
#   (i)   chain ∈ join's parents (declared bookmarks match parent set)
#   (ii)  join's parents = current bookmark targets (no staleness)
#   (iii) @ atop the join (or @ IS the join)
# Emits permissionDecision=ask on violation (never deny — violations are recoverable).
# PreToolUse:Edit|Write|MultiEdit (sync) -- reads JSON context from stdin.

set -euo pipefail

INPUT=$(cat)
# INPUT is read for protocol conformance; this hook does not inspect tool_input.
: "${INPUT:=}"

# --- jj-mode detection ---
JJ_ROOT=""
dir=$(pwd)
while [ "$dir" != "/" ]; do
  if [ -d "$dir/.jj" ]; then
    JJ_ROOT="$dir"
    break
  fi
  dir=$(dirname "$dir")
done

if [ -z "$JJ_ROOT" ]; then
  exit 0  # not a jj repo
fi

# --- Tier 3 detection: any multi-parent commit in mutable() with description "join N=..." ---
JOIN_CHANGE=$(jj log -r 'mutable()' --no-graph \
                -T 'if(parents.len() > 1 && description.starts_with("join N="), change_id ++ "\n", "")' \
                2>/dev/null | head -1)

if [ -z "$JOIN_CHANGE" ]; then
  exit 0  # tier 1 or tier 2; no diamond to verify
fi

# --- Gather join + @ topology ---
JOIN_PARENTS=$(jj log -r "$JOIN_CHANGE" --no-graph \
                 -T 'parents.map(|c| c.change_id()).join(" ")' 2>/dev/null)
AT_PARENTS=$(jj log -r '@' --no-graph \
               -T 'parents.map(|c| c.change_id()).join(" ")' 2>/dev/null)
AT_CHANGE=$(jj log -r '@' --no-graph -T 'change_id' 2>/dev/null)

# --- Check (iii): @ atop join, or @ IS join ---
if [ "$AT_CHANGE" != "$JOIN_CHANGE" ] && [ "$AT_PARENTS" != "$JOIN_CHANGE" ]; then
  cat << EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"Diamond integrity violation (iii): @ is not atop the development join. The working copy should sit at a wip commit whose sole parent is the join, OR @ itself should be the join during construction. Recovery: jj new $JOIN_CHANGE -m 'wip'. See ~/.claude/skills/jj-version-control/SKILL.md (composite maintenance invariant)."}}
EOF
  exit 0
fi

# --- Check (i) + (ii): declared bookmarks in join description match bookmarks at parent commits ---
JOIN_DESC_FIRSTLINE=$(jj log -r "$JOIN_CHANGE" --no-graph \
                       -T 'description.first_line()' 2>/dev/null)
# Parse "join N=k: a, b, c" -> sorted lines, one bookmark per line
DECLARED=$(echo "$JOIN_DESC_FIRSTLINE" | \
            sed -nE 's/^join N=[0-9]+: (.*)$/\1/p' | \
            tr ',' '\n' | \
            sed 's/^ *//;s/ *$//' | \
            grep -v '^$' | \
            sort)

# Read bookmarks at each join parent, then filter to the declared set.
# This ignores extraneous refs (e.g., remote-tracking like main@origin) that
# may be co-located on a chain tip and would otherwise cause false positives.
ACTUAL_RAW=$(
  for parent in $JOIN_PARENTS; do
    jj log -r "$parent" --no-graph \
      -T 'bookmarks.map(|b| b.name()).join("\n")' 2>/dev/null
    echo
  done | grep -v '^$' | sort -u
)
if [ -z "$DECLARED" ]; then
  ACTUAL=""
else
  ACTUAL=$( (echo "$ACTUAL_RAW" | grep -Fxf <(echo "$DECLARED") || true) | sort )
fi

if [ "$DECLARED" != "$ACTUAL" ]; then
  DECLARED_LINE=$(echo "$DECLARED" | tr '\n' ',' | sed 's/,$//')
  ACTUAL_LINE=$(echo "$ACTUAL" | tr '\n' ',' | sed 's/,$//')
  cat << EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"Diamond integrity violation (i)/(ii): join's declared bookmarks differ from current bookmark targets at its parents. Declared: '$DECLARED_LINE'. At parents: '$ACTUAL_LINE'. Often this means a bookmark advanced without the join being updated, or the join was created before all chains existed. Recovery options: (a) rewrite join with current chain tips: jj rebase -r $JOIN_CHANGE -d <bookmark1> -d <bookmark2> ...; (b) redescribe the join if the parent set is intentional: jj describe $JOIN_CHANGE -m 'join N=k: <comma-separated bookmarks>'. See ~/.claude/skills/jj-version-control/SKILL.md."}}
EOF
  exit 0
fi

# All invariants hold.
exit 0
