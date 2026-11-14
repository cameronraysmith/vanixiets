#!/usr/bin/env bash
# Task 1.7 of openspec/changes/vcs-surface-coexistence: the baseline for
# design D8. A plain `git fetch` from a linked worktree, under a global
# `fetch.prune = true` as the fleet sets it (A98), deletes a remote-tracking
# name the colocated jj primary tracks, and the primary's next `jj git import`
# drops the bookmark's remote side.
#
# In a scratch colocated clone the bookmark `feature` is pushed and tracked,
# then deleted on the forge, as a merged or another owner's branch is. The run
# is repeated with `fetch.prune = false` as the control, so the deletion is
# shown to come from pruning and not from the forge-side delete alone.
#
# Exit 0 when the pruning run loses `feature@origin` and the control keeps it
# (today's behaviour, recorded as the D8 baseline), 1 otherwise.
set -euo pipefail

scratch=$(mktemp -d "${TMPDIR:-/tmp}/vcs-prune-baseline.XXXXXX")
trap 'chmod -R u+w "$scratch"; rm -rf "$scratch"' EXIT
export HOME=$scratch/home JJ_CONFIG=$scratch/jj.toml GIT_CONFIG_GLOBAL=$scratch/gitconfig GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"
printf '[user]\nname = "t"\nemail = "t@example.invalid"\n' >"$JJ_CONFIG"
failures=0
q() { "$@" >/dev/null 2>&1; }
check() {
  local what=$1
  shift
  if "$@"; then echo "PASS: $what"; else
    echo "FAIL: $what"
    failures=$((failures + 1))
  fi
}

# Runs the scenario with the given fetch.prune and prints the primary's view of
# `feature` after the import, one `name present|absent` line per side.
scenario() {
  local prune=$1 dir=$scratch/prune-$1
  printf '[user]\n\tname = t\n\temail = t@example.invalid\n[init]\n\tdefaultBranch = main\n[fetch]\n\tprune = %s\n' "$prune" >"$GIT_CONFIG_GLOBAL"
  mkdir -p "$dir"
  git init -q --bare "$dir/origin.git"
  git clone -q "$dir/origin.git" "$dir/primary" 2>/dev/null
  echo m1 >"$dir/primary/m1" && git -C "$dir/primary" add m1 && q git -C "$dir/primary" commit -m m1
  q git -C "$dir/primary" push origin main
  (
    cd "$dir/primary"
    q jj git init --colocate
    q jj new main -m feature-1
    echo f >feature-file
    q jj bookmark create feature -r @
    q jj git push --bookmark feature
    q jj new
  )
  git -C "$dir/primary" worktree add -q -b wt "$dir/wt" main
  {
    echo "### fetch.prune = $prune"
    echo "before: $(jj -R "$dir/primary" bookmark list --all-remotes feature 2>&1 | tr '\n' ' ')"
    git -C "$dir/origin.git" branch -D feature >/dev/null
    echo "forge deletes refs/heads/feature; plain git fetch from the linked worktree:"
    git -C "$dir/wt" fetch 2>&1 | sed 's/^/  /'
    echo "refs/remotes/origin/feature: $(git -C "$dir/primary" rev-parse --verify --quiet refs/remotes/origin/feature || echo absent)"
    echo "jj git import in the primary (jj 0.47 imports on every command in a colocated workspace):"
    jj -R "$dir/primary" git import 2>&1 | sed 's/^/  /'
    echo "after: $(jj -R "$dir/primary" bookmark list --all-remotes feature 2>&1 | tr '\n' ' ')"
    echo "feature-1 commit: $(jj -R "$dir/primary" log --no-graph -r 'description(exact:"feature-1\n")' -T 'change_id.short() ++ " " ++ if(hidden, "hidden", "visible")' 2>&1)"
  } >&2
  if [[ -n $(jj -R "$dir/primary" --ignore-working-copy log --no-graph -r 'remote_bookmarks(exact:"feature", exact:"origin")' -T 'commit_id' 2>/dev/null) ]]; then
    echo "remote present"
  else
    echo "remote absent"
  fi
}

pruned=$(scenario true)
kept=$(scenario false)
check "fetch.prune = true: feature@origin gone after jj git import" test "$pruned" = "remote absent"
check "fetch.prune = false (control): feature@origin kept" test "$kept" = "remote present"
echo "failures: $failures"
((failures == 0))
