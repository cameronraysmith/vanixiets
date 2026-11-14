#!/usr/bin/env bash
# Task 1.2 of openspec/changes/vcs-surface-coexistence: concurrent devshell
# entry in linked worktrees of one scratch clone, and entry while another
# process holds the shared config.lock (A103), recorded against design D9.
#
# Devshell entry writes shared repository state twice: git-hooks.nix, when the
# tree's .pre-commit-config.yaml link is missing or stale, unsets
# core.hooksPath, reinstalls the prek hook into the common hooks directory and
# writes core.hooksPath relative to the tree (`.git/hooks` from the primary,
# absolute from a linked worktree); then modules/devshells/default.nix writes
# the absolute common-dir hooks path and runs `mergify stack setup`.
#
# Rounds:
#   concurrent  two fresh omnigent-style worktrees entered at the same moment,
#               repeated --rounds times
#   held        a fresh worktree entered while config.lock is held across its
#               whole entry, far longer than git's one-second wait
#   between     the primary entered with its hook link removed, and config.lock
#               taken the moment git-hooks.nix's relative `.git/hooks` lands and
#               held for --hold seconds, so the absolute write meets the lock
# Each round records every entry's exit status and stderr, the final
# core.hooksPath, and whether a git commit in each tree (and, after `between`,
# in a linked worktree) runs the pre-commit and commit-msg hooks.
#
# Operator use on magnetite, as an Omnigent worker:
#   ssh magnetite.zt 'sudo -n -u omnigent-cameron -i bash -s' \
#     <scripts/vcs-surface-coexistence/concurrent-devshell-entry.sh
# This script measures; it exits 0 when every step ran and 1 when a step
# could not, whatever the measured outcome. Outcomes are the OUTCOME lines.
set -euo pipefail

repo_url=https://github.com/cameronraysmith/vanixiets
ref=main
rounds=3
hold=4
keep=0
while (($#)); do
  case $1 in
    --repo-url) repo_url=$2 && shift ;;
    --ref) ref=$2 && shift ;;
    --rounds) rounds=$2 && shift ;;
    --hold) hold=$2 && shift ;;
    --keep) keep=1 ;;
    *) echo "usage: $0 [--repo-url URL] [--ref REF] [--rounds N] [--hold SECONDS] [--keep]" >&2 && exit 2 ;;
  esac
  shift
done

scratch=$(mktemp -d "${TMPDIR:-/tmp}/vcs-concurrent-entry.XXXXXX")
primary=$scratch/vanixiets
trees=()
# The fleet's direnvrc keeps each tree's nix-direnv layout under the cache
# directory, keyed by a hash of the tree's path, not in the tree.
layout_dir() { printf '%s/direnv/layouts/%s-%s' "${XDG_CACHE_HOME:-$HOME/.cache}" "$(printf '%s' "$1" | sha256sum | cut -c1-32)" "${1##*/}"; }

cleanup() {
  local t
  for t in "${trees[@]}" "$primary"; do direnv revoke "$t" >/dev/null 2>&1 || true; done
  rm -f "$primary/.git/config.lock"
  if ((keep)); then
    echo "kept: $scratch"
  else
    for t in "${trees[@]}" "$primary"; do rm -rf "$(layout_dir "$t")"; done
    chmod -R u+w "$scratch" 2>/dev/null || true
    rm -rf "$scratch"
  fi
}
trap cleanup EXIT

section() { printf '\n## %s\n' "$*"; }
outcome() { echo "OUTCOME: $*"; }

# Creates an omnigent-style worktree and sets $tree to its path.
new_tree() {
  local branch=vcs-probe/$1
  tree=$scratch/vanixiets-worktrees/vcs-probe-$1
  (cd "$primary" && LC_ALL=C git worktree add -q -b "$branch" "$tree")
  direnv allow "$tree"
  trees+=("$tree")
}

# Enters a tree's devshell, writing exit status, start and end times and
# stderr to $scratch/<label>.*
enter() {
  local dir=$1 label=$2 status=0 start
  start=$(date +%T.%N)
  (cd "$dir" && direnv exec "$dir" true) >"$scratch/$label.out" 2>"$scratch/$label.err" || status=$?
  echo "$status from $start to $(date +%T.%N)" >"$scratch/$label.status"
}

report_entry() {
  local label=$1
  echo "$label entry exit: $(cat "$scratch/$label.status")"
  grep -E 'lock|error|fatal|failed|hooksPath|git-hooks.nix|Installed|not managed' "$scratch/$label.err" 2>/dev/null |
    grep -v "ignoring the client-specified setting" | sed 's/^/  /' || true
}

hooks_path() { git -C "$primary" config --show-origin core.hooksPath || echo "core.hooksPath unset"; }

# Commits in a tree and prints which hooks git started and the Change-Id.
probe_commit() {
  local dir=$1 label=$2 status=0 ran
  echo "$label" >"$dir/vcs-probe-$label.txt"
  git -C "$dir" add "vcs-probe-$label.txt"
  GIT_TRACE=1 git -C "$dir" commit -m "vcs probe: $label" >"$scratch/commit-$label.out" 2>"$scratch/commit-$label.err" || status=$?
  ran=$(grep -oE "start_command: [^ ]*/hooks/[a-z-]+( |$)" "$scratch/commit-$label.err" | sed 's/.*hooks\///' | tr -d ' ' | sort -u | tr '\n' ' ' || true)
  printf '%s commit exit %s; hooks started: %s; Change-Id: %s\n' "$label" "$status" "${ran:-none}" \
    "$(git -C "$dir" log -1 --format=%B | grep -oE '^Change-Id: I[0-9a-f]{40}$' | cut -c12-21 || echo none)"
}

section "account"
echo "user=$(id -un) host=$(hostname) scratch=$scratch git=$(git --version) direnv=$(direnv version)"

section "clone and primary entry"
git clone --quiet --branch "$ref" "$repo_url" "$primary"
git -C "$primary" log -1 --format='%H %cs %s'
common=$(git -C "$primary" rev-parse --path-format=absolute --git-common-dir)
direnv allow "$primary"
enter "$primary" primary-initial
report_entry primary-initial
hooks_path

for ((r = 1; r <= rounds; r++)); do
  section "concurrent round $r"
  new_tree "c$r-a"
  a=$tree
  new_tree "c$r-b"
  b=$tree
  enter "$a" "c$r-a" &
  enter "$b" "c$r-b" &
  wait
  report_entry "c$r-a"
  report_entry "c$r-b"
  final=$(hooks_path)
  echo "final: $final"
  probe_commit "$a" "c$r-a"
  probe_commit "$b" "c$r-b"
  probe_commit "$primary" "c$r-primary"
  if [[ $final == *"	$common/hooks" ]]; then outcome "concurrent round $r: core.hooksPath absolute"; else outcome "concurrent round $r: core.hooksPath '$final'"; fi
done

section "held: config.lock held across a fresh tree's whole entry"
new_tree held
h=$tree
before=$(hooks_path)
echo "before: $before"
: >"$common/config.lock"
enter "$h" held
rm -f "$common/config.lock"
report_entry held
after=$(hooks_path)
echo "after: $after"
probe_commit "$h" held
probe_commit "$primary" held-primary
outcome "held: core.hooksPath before '$before', after '$after'"

section "between: lock taken after git-hooks.nix's relative write, during primary entry"
probe=${trees[0]}
rm -f "$primary/.pre-commit-config.yaml"
watcher() {
  local deadline=$((SECONDS + 600))
  while ((SECONDS < deadline)); do
    if grep -qE '^[[:space:]]*hooksPath = \.git/hooks$' "$common/config" 2>/dev/null &&
      (set -o noclobber && : >"$common/config.lock") 2>/dev/null; then
      echo "watcher: took config.lock at $(date +%T.%N) with core.hooksPath = .git/hooks"
      sleep "$hold"
      rm -f "$common/config.lock"
      return 0
    fi
  done
  echo "watcher: never saw the relative value"
}
watcher >"$scratch/watcher.log" 2>&1 &
watcher_pid=$!
enter "$primary" between
kill "$watcher_pid" 2>/dev/null || true
wait "$watcher_pid" 2>/dev/null || true
rm -f "$common/config.lock"
cat "$scratch/watcher.log"
report_entry between
final=$(hooks_path)
echo "final: $final"
probe_commit "$primary" between-primary
probe_commit "$probe" between-linked
outcome "between: core.hooksPath '$final'; linked-tree commit: $(grep -c 'start_command: [^ ]*/hooks/' "$scratch/commit-between-linked.err" || true) hooks started"

section "hooks directory at the end"
find "$common/hooks" -type f ! -name '*.sample' -printf '%P\n' | sort | sed 's/^/  /'
