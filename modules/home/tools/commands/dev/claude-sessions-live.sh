#!/usr/bin/env bash
# List live Claude Code CLI sessions grouped by working directory
set -euo pipefail

mode=table
case "${1:-}" in
  -h|--help)
    cat <<'HELP'
List live Claude Code CLI sessions grouped by working directory

Usage: claude-sessions-live [--cwds | --pids | --table]

Enumerates running `claude` CLI processes on the local machine, resolves
each process's working directory via lsof, and groups by cwd.

Options:
  --table   (default) Three-column report: count, cwd, space-separated pids
  --cwds    One unique cwd per line
  --pids    One pid per line (raw, unsorted)
  -h, --help  Show this help

Notes:
  - Matches only the bare `claude` executable (excludes the Claude desktop
    app and editor processes whose argv merely contain the substring).
  - Reports the per-process cwd at the moment of inspection; long-lived
    sessions may have drifted from where they were launched.
HELP
    exit 0
    ;;
  --table) mode=table ;;
  --cwds)  mode=cwds ;;
  --pids)  mode=pids ;;
  "") ;;
  *)
    echo "Error: unknown argument: $1" >&2
    echo "Try 'claude-sessions-live --help' for more information." >&2
    exit 1
    ;;
esac

pids=$(ps -axo pid,command= | awk '$2 ~ /(^|\/)claude$/ {print $1}')

if [ -z "$pids" ]; then
  exit 0
fi

if [ "$mode" = "pids" ]; then
  printf '%s\n' "$pids"
  exit 0
fi

# Resolve each pid to its cwd via lsof; emit "<cwd>\t<pid>" lines.
rows=$(while read -r pid; do
  cwd=$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null \
        | awk '/^n/{sub(/^n/,"");print;exit}')
  [ -n "$cwd" ] && printf '%s\t%s\n' "$cwd" "$pid"
done <<<"$pids")

if [ -z "$rows" ]; then
  exit 0
fi

if [ "$mode" = "cwds" ]; then
  printf '%s\n' "$rows" | awk -F'\t' '{print $1}' | sort -u
  exit 0
fi

# Table mode: group by cwd, count, list pids; sort by count desc then cwd.
printf '%s\n' "$rows" \
  | sort \
  | awk -F'\t' '
      { d[$1]=(d[$1]=="" ? $2 : d[$1] " " $2); n[$1]++ }
      END {
        for (k in n) printf "%d\t%s\t%s\n", n[k], k, d[k]
      }' \
  | sort -k1,1nr -k2,2 \
  | awk -F'\t' '
      { if (length($2) > w) w = length($2) }
      { rows[NR] = $0 }
      END {
        for (i = 1; i <= NR; i++) {
          split(rows[i], f, "\t")
          printf "%-3s  %-*s  %s\n", f[1], w, f[2], f[3]
        }
      }'
