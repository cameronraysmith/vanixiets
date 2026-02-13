#!/usr/bin/env bash
# Collect repository sparsity metrics and output JSON.
# Run from the root of the repository being evaluated.
set -euo pipefail

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: not inside a git repository" >&2
  exit 1
fi

platform="$(uname -s)"

# --- File count ---
file_count=$(git ls-files | wc -l | tr -d ' ')

# --- Working tree size ---
if [ "$platform" = "Darwin" ]; then
  tree_size_bytes=$(git ls-files -z | xargs -0 stat -f%z 2>/dev/null | paste -sd+ - | bc)
else
  tree_size_bytes=$(git ls-files -z | xargs -0 stat --format=%s 2>/dev/null | paste -sd+ - | bc)
fi

format_bytes() {
  local bytes=$1
  if [ "$bytes" -ge 1073741824 ]; then
    printf "%.1f GB" "$(echo "scale=1; $bytes / 1073741824" | bc)"
  elif [ "$bytes" -ge 1048576 ]; then
    printf "%.1f MB" "$(echo "scale=1; $bytes / 1048576" | bc)"
  elif [ "$bytes" -ge 1024 ]; then
    printf "%.1f KB" "$(echo "scale=1; $bytes / 1024" | bc)"
  else
    echo "${bytes} B"
  fi
}

tree_size_human=$(format_bytes "$tree_size_bytes")

# --- Change locality ---
total=$file_count
if [ "$total" -eq 0 ]; then
  avg_changed=0
  change_locality="0"
  change_locality_pct="0%"
else
  avg_changed=$(git log --oneline -100 --numstat \
    | awk '/^[0-9]/{n++} /^[a-f0-9]+ /{if(n>0){sum+=n; c++; n=0}} END{if(n>0){sum+=n; c++} if(c>0) print int(sum/c); else print 0}')
  change_locality=$(echo "scale=6; $avg_changed / $total" | bc)
  change_locality_pct=$(echo "scale=2; $change_locality * 100" | bc | sed 's/$/%/')
fi

cat <<EOF
{
  "file_count": $file_count,
  "tree_size_bytes": $tree_size_bytes,
  "tree_size_human": "$tree_size_human",
  "change_locality": $change_locality,
  "change_locality_pct": "$change_locality_pct",
  "avg_files_per_commit": $avg_changed,
  "platform": "$platform"
}
EOF
