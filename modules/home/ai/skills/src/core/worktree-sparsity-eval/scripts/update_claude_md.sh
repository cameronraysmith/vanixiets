#!/usr/bin/env bash
# Update CLAUDE.md with worktree sparsity metrics.
# Reads JSON from stdin (output of collect_metrics.sh).
# Usage: collect_metrics.sh | update_claude_md.sh <path-to-CLAUDE.md>
set -euo pipefail

claude_md="${1:?Usage: collect_metrics.sh | update_claude_md.sh <path-to-CLAUDE.md>}"

json=$(cat)

file_count=$(echo "$json" | grep '"file_count"' | grep -o '[0-9]*')
tree_size_bytes=$(echo "$json" | grep '"tree_size_bytes"' | grep -o '[0-9]*')
tree_size_human=$(echo "$json" | grep '"tree_size_human"' | sed 's/.*: *"\(.*\)".*/\1/')
change_locality=$(echo "$json" | grep '"change_locality"' | head -1 | sed 's/.*: *\([0-9.]*\).*/\1/')
change_locality_pct=$(echo "$json" | grep '"change_locality_pct"' | sed 's/.*: *"\(.*\)".*/\1/')

# --- Resolve symlink ---
if [ -L "$claude_md" ]; then
  if command -v greadlink >/dev/null 2>&1; then
    target=$(greadlink -f "$claude_md")
  elif readlink -f "$claude_md" >/dev/null 2>&1; then
    target=$(readlink -f "$claude_md")
  else
    target=$(perl -MCwd -e 'print Cwd::realpath($ARGV[0])' "$claude_md")
  fi
  target_repo=$(git -C "$(dirname "$target")" rev-parse --show-toplevel 2>/dev/null || dirname "$target")
else
  target=$(cd "$(dirname "$claude_md")" && pwd)/$(basename "$claude_md")
  target_repo=$(git -C "$(dirname "$target")" rev-parse --show-toplevel 2>/dev/null || dirname "$target")
fi

echo "Resolved CLAUDE.md: $target" >&2
echo "Target repository: $target_repo" >&2

# --- Determine recommendation ---
recommend="no"
file_count_meets="no"
size_meets="no"
locality_meets="no"

if [ "$file_count" -gt 10000 ]; then file_count_meets="yes"; fi
if [ "$tree_size_bytes" -gt 524288000 ]; then size_meets="yes"; fi
locality_check=$(echo "$change_locality < 0.01" | bc -l)
if [ "$locality_check" -eq 1 ]; then locality_meets="yes"; fi

if [ "$file_count_meets" = "yes" ] && [ "$size_meets" = "yes" ] && [ "$locality_meets" = "yes" ]; then
  recommend="yes"
fi

# --- Format file count with commas ---
file_count_fmt=$(printf "%'d" "$file_count")

# --- Check for existing metrics ---
sentinel_start="<!-- worktree-sparsity-metrics:start -->"
sentinel_end="<!-- worktree-sparsity-metrics:end -->"

has_existing="no"
if grep -q "$sentinel_start" "$target" 2>/dev/null; then
  has_existing="yes"
fi

if [ "$has_existing" = "yes" ]; then
  existing_section=$(sed -n "/$sentinel_start/,/$sentinel_end/p" "$target")
  existing_file_count=$(echo "$existing_section" | grep "File count" | awk -F'|' '{gsub(/[^0-9]/, "", $3); print $3}')
  existing_locality_pct=$(echo "$existing_section" | grep "Change locality" | sed -n 's/.*| *\([0-9.]*\)%.*/\1/p' | head -1)
  existing_recommend=$(echo "$existing_section" | grep -c "Use sparse checkout" || true)

  skip_update="yes"

  if [ -n "$existing_file_count" ] && [ "$existing_file_count" -gt 0 ]; then
    fc_delta=$(echo "scale=4; ($file_count - $existing_file_count) / $existing_file_count" | bc)
    fc_delta_abs=$(echo "$fc_delta" | tr -d '-')
    fc_exceeds=$(echo "$fc_delta_abs > 0.05" | bc -l)
    if [ "$fc_exceeds" -eq 1 ]; then
      fc_pct=$(echo "scale=1; $fc_delta * 100" | bc)
      echo "File count: $existing_file_count -> $file_count (${fc_pct}%)" >&2
      skip_update="no"
    fi
  else
    skip_update="no"
  fi

  if [ -n "$existing_locality_pct" ]; then
    existing_locality_raw=$(echo "scale=6; $existing_locality_pct / 100" | bc)
    if [ "$(echo "$existing_locality_raw > 0" | bc -l)" -eq 1 ]; then
      loc_delta=$(echo "scale=4; ($change_locality - $existing_locality_raw) / $existing_locality_raw" | bc)
      loc_delta_abs=$(echo "$loc_delta" | tr -d '-')
      loc_exceeds=$(echo "$loc_delta_abs > 0.05" | bc -l)
      if [ "$loc_exceeds" -eq 1 ]; then
        loc_pct=$(echo "scale=1; $loc_delta * 100" | bc)
        echo "Change locality: ${existing_locality_pct}% -> $change_locality_pct (${loc_pct}%)" >&2
        skip_update="no"
      fi
    else
      skip_update="no"
    fi
  else
    skip_update="no"
  fi

  new_recommend_count=0
  if [ "$recommend" = "yes" ]; then new_recommend_count=1; fi
  if [ "$existing_recommend" -ne "$new_recommend_count" ]; then
    echo "Recommendation changed" >&2
    skip_update="no"
  fi

  if [ "$skip_update" = "yes" ]; then
    echo "No meaningful change (all deltas < 5%, recommendation unchanged). Skipping update." >&2
    exit 0
  fi
fi

# --- Build replacement section ---
today=$(date +%Y-%m-%d)

section="## Worktree sparsity metrics

$sentinel_start
| Metric | Value | Threshold | Meets |
|---|---|---|---|
| File count | $file_count_fmt | > 10,000 | $file_count_meets |
| Working tree size | $tree_size_human | > 500 MB | $size_meets |
| Change locality | $change_locality_pct | < 1% | $locality_meets |
"

if [ "$recommend" = "yes" ]; then
  section+="
Recommendation: Use sparse checkout for worktrees.

\`\`\`bash
git worktree add --no-checkout .worktrees/{ID}-descriptor -b {ID}-descriptor
cd .worktrees/{ID}-descriptor
git sparse-checkout init --cone
git sparse-checkout set <paths-relevant-to-task>
git checkout
\`\`\`
"
else
  section+="
Recommendation: Standard \`git worktree add\` suffices. Sparse checkout not needed.
"
fi

section+="Last evaluated: $today
$sentinel_end"

# --- Write to file ---
if [ "$has_existing" = "yes" ]; then
  awk -v replacement="$section" '
    /^## Worktree sparsity metrics/ { skip=1; printed=0 }
    /<!-- worktree-sparsity-metrics:end -->/ {
      if(skip && !printed) { print replacement; printed=1 }
      skip=0
      next
    }
    !skip { print }
  ' "$target" > "${target}.tmp" && mv "${target}.tmp" "$target"
  echo "Updated existing sparsity metrics section in $target" >&2
else
  printf '\n%s\n' "$section" >> "$target"
  echo "Appended sparsity metrics section to $target" >&2
fi

echo "TARGET_FILE=$target"
echo "TARGET_REPO=$target_repo"
