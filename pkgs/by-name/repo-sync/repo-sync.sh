#!/usr/bin/env bash
# shellcheck shell=bash

usage() {
  cat <<'USAGE'
repo-sync - conservatively update git and jj repositories discovered beneath one
or more paths. jj-colocated repositories are fetched with `jj git fetch`; plain
git repositories are fast-forwarded to their upstream and are never force-updated,
merge-committed, or switched. Dirty, detached, upstream-less, or diverged
repositories are skipped with a notice.

Usage:
  repo-sync [options] PATH...

Arguments:
  PATH...            One or more directories to search recursively for
                     repositories. At least one is required; there is no
                     current-directory default, to avoid accidental large walks.

Options:
  -n, --dry-run      Print the planned per-repo action without mutating anything.
  --no-tags          Do not fetch tags (default: fetch tags).
  -j, --jobs N       Maximum repositories to process concurrently (default: 6).
  -h, --help         Show this help and exit.

Per-repo behavior:
  jj (colocated)     `jj -R <repo> git fetch`; never `git pull` (detached HEAD is
                     normal for jj, so `git pull` is the wrong verb).
  git                fetch, then `git merge --ff-only @{u}`. Skipped when the tree
                     is dirty (tracked changes; untracked files do not block),
                     HEAD is detached, there is no upstream tracking branch, or
                     the merge would not be a fast-forward (diverged).

Output is one line per repository (updated / jj-fetched / skip / failed, or plan
under --dry-run) followed by a summary tally.
USAGE
}

git_dirty() {
  local r="$1"
  if ! git -C "$r" diff --quiet 2>/dev/null || ! git -C "$r" diff --cached --quiet 2>/dev/null; then
    return 0
  fi
  return 1
}

git_detached() {
  local r="$1"
  if git -C "$r" symbolic-ref -q HEAD >/dev/null 2>&1; then
    return 1
  fi
  return 0
}

git_has_upstream() {
  local r="$1"
  git -C "$r" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1
}

emit() {
  local kind="$1" path="$2" detail="${3:-}"
  case "$kind" in
    updated)
      if [ -n "$detail" ]; then
        printf 'updated: %s (%s)\n' "$path" "$detail"
      else
        printf 'updated: %s\n' "$path"
      fi
      printf 'updated\n' >>"$tally"
      ;;
    jj-fetched)
      printf 'jj-fetched: %s\n' "$path"
      printf 'jj-fetched\n' >>"$tally"
      ;;
    skip)
      printf 'skip: %s (%s)\n' "$path" "$detail"
      printf 'skipped\n' >>"$tally"
      ;;
    fail)
      printf 'failed: %s (%s)\n' "$path" "$detail"
      printf 'failed\n' >>"$tally"
      ;;
    plan)
      printf 'plan: %s (%s)\n' "$path" "$detail"
      printf 'planned\n' >>"$tally"
      ;;
  esac
}

process_repo() {
  local repo="$1"

  if [ -e "$repo/.jj" ]; then
    if [ "$dry_run" = 1 ]; then
      emit plan "$repo" "would jj git fetch"
      return 0
    fi
    if jj -R "$repo" git fetch >/dev/null 2>&1; then
      emit jj-fetched "$repo"
    else
      emit fail "$repo" "jj git fetch"
    fi
    return 0
  fi

  if git_dirty "$repo"; then emit skip "$repo" "dirty tree"; return 0; fi
  if git_detached "$repo"; then emit skip "$repo" "detached head"; return 0; fi
  if ! git_has_upstream "$repo"; then emit skip "$repo" "no upstream"; return 0; fi

  if [ "$dry_run" = 1 ]; then
    emit plan "$repo" "would fetch and fast-forward"
    return 0
  fi

  if [ "$tags" = 1 ]; then
    if ! git -C "$repo" fetch --tags >/dev/null 2>&1; then emit fail "$repo" "fetch"; return 0; fi
  else
    if ! git -C "$repo" fetch --no-tags >/dev/null 2>&1; then emit fail "$repo" "fetch"; return 0; fi
  fi

  local localrev remoterev baserev
  localrev=$(git -C "$repo" rev-parse HEAD 2>/dev/null) || { emit fail "$repo" "rev-parse head"; return 0; }
  remoterev=$(git -C "$repo" rev-parse '@{u}' 2>/dev/null) || { emit fail "$repo" "rev-parse upstream"; return 0; }
  if [ "$localrev" = "$remoterev" ]; then emit updated "$repo" "already up to date"; return 0; fi
  baserev=$(git -C "$repo" merge-base HEAD '@{u}' 2>/dev/null) || { emit fail "$repo" "merge-base"; return 0; }
  if [ "$baserev" = "$remoterev" ]; then emit updated "$repo" "local ahead of upstream"; return 0; fi
  if [ "$baserev" != "$localrev" ]; then emit skip "$repo" "diverged (non-fast-forward)"; return 0; fi
  if git -C "$repo" merge --ff-only '@{u}' >/dev/null 2>&1; then
    emit updated "$repo" "fast-forwarded"
  else
    emit fail "$repo" "ff merge"
  fi
  return 0
}

dry_run=0
tags=1
jobs=6
declare -a paths=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    -n | --dry-run) dry_run=1 ;;
    --no-tags) tags=0 ;;
    -j=* | --jobs=*) jobs="${1#*=}" ;;
    -j | --jobs)
      if [ "$#" -lt 2 ]; then
        printf 'error: %s requires a value\n\n' "$1" >&2
        usage >&2
        exit 2
      fi
      shift
      jobs="$1"
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    --)
      shift
      while [ "$#" -gt 0 ]; do
        paths+=("$1")
        shift
      done
      break
      ;;
    -*)
      printf 'error: unknown option: %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
    *) paths+=("$1") ;;
  esac
  shift
done

case "$jobs" in
  '' | *[!0-9]*)
    printf 'error: --jobs must be a positive integer: %s\n\n' "$jobs" >&2
    usage >&2
    exit 2
    ;;
esac
if [ "$jobs" -lt 1 ]; then
  printf 'error: --jobs must be >= 1\n\n' >&2
  usage >&2
  exit 2
fi

if [ "${#paths[@]}" -eq 0 ]; then
  printf 'error: at least one PATH is required\n\n' >&2
  usage >&2
  exit 2
fi

for p in "${paths[@]}"; do
  if [ ! -d "$p" ]; then
    printf 'error: not a directory: %s\n' "$p" >&2
    exit 2
  fi
done

tally=$(mktemp)
trap 'rm -f "$tally"' EXIT

declare -a markers=()
while IFS= read -r -d '' m; do
  markers+=("$m")
done < <(fd --hidden --no-ignore --absolute-path --prune --print0 '^\.(git|jj)$' "${paths[@]}")

declare -A seen=()
declare -a roots=()
for m in "${markers[@]}"; do
  root=$(dirname "$m")
  if [ -z "${seen[$root]:-}" ]; then
    seen[$root]=1
    roots+=("$root")
  fi
done

if [ "${#roots[@]}" -eq 0 ]; then
  printf 'notice: no git or jj repositories found under the given paths\n' >&2
fi

running=0
for root in "${roots[@]}"; do
  process_repo "$root" &
  running=$((running + 1))
  if [ "$running" -ge "$jobs" ]; then
    wait -n 2>/dev/null || true
    running=$((running - 1))
  fi
done
wait

read -r c_updated c_jjfetched c_skipped c_failed c_planned < <(
  awk '{c[$0]++} END {print c["updated"]+0, c["jj-fetched"]+0, c["skipped"]+0, c["failed"]+0, c["planned"]+0}' "$tally"
)

if [ "$dry_run" = 1 ]; then
  printf 'summary: %d planned, %d skipped\n' "$c_planned" "$c_skipped"
else
  printf 'summary: %d updated, %d jj-fetched, %d skipped, %d failed\n' \
    "$c_updated" "$c_jjfetched" "$c_skipped" "$c_failed"
fi
