#!/usr/bin/env bash
# Search Claude Code session JSONL files for co-occurring terms.
# Usage: search_sessions.sh [-d dir]... [-i] [-n topN] term1 term2 ...
#
# Finds sessions containing ALL specified terms and ranks by total match density.
# -d restricts search to specific project directories under ~/.claude/projects/.
# Without -d, searches all projects.

set -euo pipefail

DIRS=()
CASE_FLAG=""
TOP_N=10

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d) DIRS+=("$2"); shift 2 ;;
    -i) CASE_FLAG="-i"; shift ;;
    -n) TOP_N="$2"; shift 2 ;;
    --) shift; break ;;
    -*) echo "Unknown flag: $1" >&2; exit 1 ;;
    *) break ;;
  esac
done

TERMS=("$@")
if [[ ${#TERMS[@]} -eq 0 ]]; then
  echo "Usage: search_sessions.sh [-d project-dir]... [-i] [-n topN] term1 [term2 ...]" >&2
  exit 1
fi

BASE="$HOME/.claude/projects"

# Build search paths
SEARCH_PATHS=()
if [[ ${#DIRS[@]} -eq 0 ]]; then
  SEARCH_PATHS+=("$BASE")
else
  for d in "${DIRS[@]}"; do
    if [[ "$d" == /* ]]; then
      SEARCH_PATHS+=("$d")
    else
      SEARCH_PATHS+=("$BASE/$d")
    fi
  done
fi

for p in "${SEARCH_PATHS[@]}"; do
  if [[ ! -d "$p" ]]; then
    echo "Directory not found: $p" >&2
    exit 1
  fi
done

# Phase 1: intersect — find files matching ALL terms
CANDIDATES=""
for term in "${TERMS[@]}"; do
  # shellcheck disable=SC2086
  MATCHES=$(rg -l $CASE_FLAG --type jsonl "$term" "${SEARCH_PATHS[@]}" 2>/dev/null || true)
  if [[ -z "$MATCHES" ]]; then
    echo "No sessions match term: $term" >&2
    exit 0
  fi
  if [[ -z "$CANDIDATES" ]]; then
    CANDIDATES="$MATCHES"
  else
    CANDIDATES=$(comm -12 <(echo "$CANDIDATES" | sort) <(echo "$MATCHES" | sort))
  fi
  if [[ -z "$CANDIDATES" ]]; then
    echo "No sessions match all terms simultaneously." >&2
    exit 0
  fi
done

# Phase 2: rank — count matches per term, compute total, sort descending
{
  echo "FILE|SIZE|$(printf '%s|' "${TERMS[@]}")TOTAL"
  while IFS= read -r f; do
    total=0
    counts=""
    for term in "${TERMS[@]}"; do
      # shellcheck disable=SC2086
      c=$(rg -c $CASE_FLAG "$term" "$f" 2>/dev/null || echo 0)
      total=$((total + c))
      counts="${counts}${c}|"
    done
    sz=$(du -h "$f" | cut -f1)
    short="${f#"$BASE"/}"
    echo "${short}|${sz}|${counts}${total}"
  done <<< "$CANDIDATES"
} | (read -r header; echo "$header"; sort -t'|' -k"$((${#TERMS[@]} + 3))" -rn | head -n "$TOP_N") | column -t -s'|'
