#!/usr/bin/env bash
# Tasks 1.3 to 1.6 of openspec/changes/vcs-surface-coexistence: the read-only
# drift detector's acceptance tests. The detector is task 4.1; this script
# fixes the interface it implements.
#
# Detector interface
#   Invocation: "$VCS_DRIFT_DETECTOR" <path inside the primary working tree>
#     (or --detector CMD here). It may read anything and MUST write nothing:
#     no ref, config, index, op log, admin directory or tree file changes.
#   Exit status: 0 when it reports no drift, 1 when it reports drift, 2 or
#     more on error.
#   Output on stdout: one record per line, tab-separated, `kind<TAB>path<TAB>detail`,
#     where path is absolute with symlinks resolved. Inventory kinds name what
#     is live, drift kinds name what is wrong; a path may carry several kinds.
#     worktree             a live git worktree; detail: its branch ref or `detached`
#     workspace            a live jj workspace of the primary's history store; detail: its name
#     join-base            a git worktree whose branch carries commits, not on
#                          origin/main, of a chain other than its own (it was
#                          based on a development join); detail: the branch
#     behind-main          a git worktree whose branch lacks commits of origin/main;
#                          detail: the branch and `<n> behind`
#     stray-history-store  a tree other than the primary holding its own
#                          `.jj/repo` directory; detail: the store's git target
#     orphaned-tree        a directory whose `.git` file names an admin
#                          directory that does not exist; detail: the named gitdir
#     prunable-worktree    a record under the common dir's worktrees/ whose
#                          directory is gone; detail: the record's name
#     stale-workspace      a jj workspace record whose directory is gone; detail: its name
#   A forgotten jj workspace is reported under no kind.
#   Directories scanned for orphaned trees and stray history stores: every git
#   worktree, and the immediate children of the primary's parent directory, of
#   <parent>/<repo>-worktrees/ and of <primary>/.claude/worktrees/.
#
# Fixture mode (default): builds a scratch colocated repository in which:
#   wt-join     is based on a development join of chains chain-a and chain-b (1.3)
#   wt-behind   is behind origin/main (1.3)
#   wt-clean    is on origin/main plus its own commit, and must be named by no drift kind
#   wt-stray    is a linked worktree with `jj git init --colocate` run in it (1.4)
#   repo-orphan is a sibling whose .git file names a removed admin directory (1.4)
#   repo-wv     is both, as ../vanixiets-wv-preview-port was on 2026-11-14 (1.4)
#   ws-gone     is a jj workspace whose directory was removed (1.5)
#   ws-forgotten is a jj workspace that was forgotten and removed (1.5)
# then runs the detector and asserts its records and that a listing of refs,
# admin directories, `.jj/repo/op_heads` and every tree's files is unchanged.
#
# --live REPO (1.6): runs the detector read-only against REPO and asserts it
# names ../vanixiets-wv-preview-port and ../vanixiets-wv-webkit-screenshot,
# or that they are gone, with refs, admin directories, op heads and every
# tree's VCS metadata unchanged.
#
# Exit 0 when every assertion holds, 1 otherwise; the FAIL lines say which.
set -euo pipefail

detector=${VCS_DRIFT_DETECTOR:-}
live=
keep=0
while (($#)); do
  case $1 in
    --detector) detector=$2 && shift ;;
    --live) live=$2 && shift ;;
    --keep) keep=1 ;;
    *) echo "usage: $0 [--detector CMD] [--live REPO] [--keep]" >&2 && exit 2 ;;
  esac
  shift
done

failures=0
section() { printf '\n## %s\n' "$*"; }
pass() { echo "PASS: $*"; }
fail() {
  echo "FAIL: $*"
  failures=$((failures + 1))
}
check() {
  local what=$1
  shift
  if "$@"; then pass "$what"; else fail "$what"; fi
}
canon() { (cd "$1" && pwd -P); }
not() { ! "$@"; }

# Every path under the given roots with its type and content digest, symlink
# target or nothing for directories; sorted, so two listings diff cleanly.
listing() {
  local root
  for root in "$@"; do
    [[ -e $root ]] || continue
    find "$root" \( -type f -o -type l -o -type d \) -print0
  done | sort -z | while IFS= read -r -d '' p; do
    if [[ -L $p ]]; then
      printf 'l %s -> %s\n' "$p" "$(readlink "$p")"
    elif [[ -d $p ]]; then
      printf 'd %s\n' "$p"
    else
      printf 'f %s %s\n' "$p" "$(sha256sum <"$p" | cut -c1-64)"
    fi
  done
}

detector_cmd() {
  if [[ -z $detector ]]; then
    fail "drift detector missing: VCS_DRIFT_DETECTOR is unset and --detector not given (task 4.1 provides it)"
    return 1
  fi
  if ! command -v "${detector%% *}" >/dev/null 2>&1; then
    fail "drift detector missing: '${detector%% *}' is not an executable command (task 4.1 provides it)"
    return 1
  fi
}

# Runs the detector once against $1, storing records in $report and its
# status in $detector_status.
run_detector() {
  detector_status=0
  # shellcheck disable=SC2086 # the detector may be given as a command with arguments
  $detector "$1" >"$report" 2>"$report.err" || detector_status=$?
  echo "detector exit: $detector_status"
  sed 's/^/  /' "$report"
  [[ -s $report.err ]] && sed 's/^/  stderr: /' "$report.err"
  return 0
}

has_record() { awk -F'\t' -v k="$1" -v p="$2" '$1 == k && $2 == p { found = 1 } END { exit !found }' "$report"; }
names_path_as_drift() {
  awk -F'\t' -v p="$1" '$2 == p && $1 != "worktree" && $1 != "workspace" { found = 1 } END { exit !found }' "$report"
}
mentions() { grep -qF -- "$1" "$report"; }

live_mode() {
  local repo common parent ws_names
  repo=$(canon "$live")
  common=$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)
  parent=${repo%/*}
  scratch=$(mktemp -d "${TMPDIR:-/tmp}/vcs-drift-live.XXXXXX")
  report=$scratch/report
  trap 'rm -rf "$scratch"' EXIT

  # VCS metadata only: hashing every tracked file of a live repository is
  # out of proportion, and the detector's writes would land in metadata.
  live_listing() {
    git -C "$repo" for-each-ref --format='%(refname) %(objectname)'
    listing "$common/worktrees" "$repo/.jj/repo/op_heads" "$repo/.jj/working_copy"
    local d
    for d in "$parent"/*/ "$parent/${repo##*/}-worktrees"/*/; do
      [[ $d == "$repo/" ]] && continue
      [[ -e $d/.git || -e $d/.jj ]] || continue
      listing "$d.git" "$d.jj/repo/op_heads" "$d.jj/working_copy"
    done
  }

  section "live listing before: $repo"
  git -C "$repo" worktree list --porcelain
  jj -R "$repo" --ignore-working-copy workspace list
  live_listing >"$scratch/before"
  wc -l <"$scratch/before"

  section "detector against $repo"
  if detector_cmd; then
    run_detector "$repo"
    check "detector exits 0 or 1" test "$detector_status" -le 1
    local wv
    for wv in vanixiets-wv-preview-port vanixiets-wv-webkit-screenshot; do
      if [[ -e $parent/$wv ]]; then
        check "report names $parent/$wv" names_path_as_drift "$parent/$wv"
      else
        pass "$parent/$wv is gone (retired)"
      fi
    done
    ws_names=$(jj -R "$repo" --ignore-working-copy workspace list -T 'name ++ "\n"' | sort)
    check "reported jj workspaces match jj workspace list" \
      test "$(awk -F'\t' '$1 == "workspace" || $1 == "stale-workspace" { print $3 }' "$report" | sort)" = "$ws_names"
  fi

  section "live listing after"
  live_listing >"$scratch/after"
  if cmp -s "$scratch/before" "$scratch/after"; then
    pass "refs, admin directories, op heads and tree metadata unchanged"
  else
    diff "$scratch/before" "$scratch/after" | head -40 | sed 's/^/  /'
    fail "the detector run changed VCS state"
  fi
}

fixture_mode() {
  scratch=$(mktemp -d "${TMPDIR:-/tmp}/vcs-drift-fixture.XXXXXX")
  scratch=$(canon "$scratch")
  report=$scratch/report
  if ((keep)); then
    trap 'echo "kept: $scratch"' EXIT
  else
    trap 'chmod -R u+w "$scratch"; rm -rf "$scratch"' EXIT
  fi
  export HOME=$scratch/home JJ_CONFIG=$scratch/jj.toml GIT_CONFIG_GLOBAL=$scratch/gitconfig GIT_CONFIG_NOSYSTEM=1
  mkdir -p "$HOME"
  printf '[user]\nname = "t"\nemail = "t@example.invalid"\n' >"$JJ_CONFIG"
  printf '[user]\n\tname = t\n\temail = t@example.invalid\n[init]\n\tdefaultBranch = main\n' >"$GIT_CONFIG_GLOBAL"
  local root=$scratch/projects
  local primary=$root/vanixiets origin=$scratch/origin.git
  local common=$primary/.git
  mkdir -p "$root"
  q() { "$@" >/dev/null 2>&1; }
  commit() { echo "$2" >"$1/$2" && git -C "$1" add "$2" && q git -C "$1" commit -m "$2"; }

  section "fixture"
  git init -q --bare "$origin"
  git clone -q "$origin" "$primary" 2>/dev/null
  commit "$primary" m1
  q git -C "$primary" push origin main
  (cd "$primary" && q jj git init --colocate)

  # 1.3: behind main
  git -C "$primary" worktree add -q -b wt-behind "$root/vanixiets-worktrees/wt-behind" main
  commit "$root/vanixiets-worktrees/wt-behind" behind-own
  local tmp=$scratch/advance
  git clone -q "$origin" "$tmp"
  commit "$tmp" m2
  q git -C "$tmp" push origin main
  (cd "$primary" && q jj git fetch)

  # 1.3: a development join of two chains, and a tree based on it
  (
    cd "$primary"
    q jj new 'main@origin' -m chain-a-1 && q jj bookmark create chain-a -r @
    q jj new 'main@origin' -m chain-b-1 && q jj bookmark create chain-b -r @
    q jj new chain-a chain-b -m join
    q jj new -m wip
  )
  git -C "$primary" worktree add -q -b wt-join "$root/vanixiets-worktrees/wt-join"
  commit "$root/vanixiets-worktrees/wt-join" join-own
  git -C "$primary" worktree add -q -b wt-clean "$root/vanixiets-worktrees/wt-clean" origin/main
  commit "$root/vanixiets-worktrees/wt-clean" clean-own

  # 1.4: a stray history store in a linked tree, and orphaned trees
  git -C "$primary" worktree add -q -b wt-stray "$root/vanixiets-worktrees/wt-stray" origin/main
  echo "jj git init --colocate in a linked worktree:"
  (cd "$root/vanixiets-worktrees/wt-stray" && jj git init --colocate 2>&1 | sed 's/^/  /')
  git -C "$primary" worktree add -q --detach "$root/repo-orphan" origin/main
  rm -rf "$common/worktrees/repo-orphan"
  git -C "$primary" worktree add -q --detach "$root/repo-wv" origin/main
  (cd "$root/repo-wv" && q jj git init --colocate)
  rm -rf "$common/worktrees/repo-wv"

  # 1.5: a jj workspace whose directory is gone, and a forgotten one
  (
    cd "$primary"
    q jj workspace add --name ws-gone "$root/ws-gone"
    q jj workspace add --name ws-forgotten "$root/ws-forgotten"
    q jj workspace forget ws-forgotten
  )
  rm -rf "$root/ws-gone" "$root/ws-forgotten"
  # An edit jj has not snapshotted, as a live development join usually has: any
  # jj command that snapshots the primary then records an operation.
  echo pending >"$primary/pending-edit"

  git -C "$primary" worktree list --porcelain | sed 's/^/  /'
  echo "jj workspace list:"
  jj -R "$primary" --ignore-working-copy workspace list | sed 's/^/  /'
  local jj_names
  jj_names=$(jj -R "$primary" --ignore-working-copy workspace list -T 'name ++ "\n"' | sort)
  check "fixture: jj lists ws-gone and not ws-forgotten" \
    test "$jj_names" = "$(printf 'default\nws-gone')"
  check "fixture: wt-join carries both chains" \
    test "$(git -C "$primary" rev-list --count origin/main..wt-join)" -ge 4
  check "fixture: wt-behind is behind origin/main" \
    test "$(git -C "$primary" rev-list --count wt-behind..origin/main)" -ge 1
  check "fixture: wt-stray holds its own history store" test -d "$root/vanixiets-worktrees/wt-stray/.jj/repo"

  local -a roots=("$origin" "$root")
  listing "${roots[@]}" >"$scratch/before"
  git -C "$primary" for-each-ref --format='%(refname) %(objectname)' >>"$scratch/before"

  section "detector against the fixture"
  if detector_cmd; then
    run_detector "$primary"
    check "detector exits 1 (drift found)" test "$detector_status" = 1
    local wt=$root/vanixiets-worktrees
    check "1.3: wt-join named join-base" has_record join-base "$wt/wt-join"
    check "1.3: wt-behind named behind-main" has_record behind-main "$wt/wt-behind"
    check "1.3: wt-clean named by no drift kind" not names_path_as_drift "$wt/wt-clean"
    check "1.4: wt-stray named stray-history-store" has_record stray-history-store "$wt/wt-stray"
    check "1.4: repo-orphan named orphaned-tree" has_record orphaned-tree "$root/repo-orphan"
    check "1.4: repo-wv named orphaned-tree" has_record orphaned-tree "$root/repo-wv"
    check "1.4: repo-wv named stray-history-store" has_record stray-history-store "$root/repo-wv"
    check "1.4: primary not named stray-history-store" not has_record stray-history-store "$primary"
    check "1.5: ws-gone named stale-workspace" has_record stale-workspace "$root/ws-gone"
    check "1.5: ws-forgotten not reported" not mentions ws-forgotten
    check "1.5: reported jj workspaces match jj workspace list" \
      test "$(awk -F'\t' '$1 == "workspace" || $1 == "stale-workspace" { print $3 }' "$report" | sort)" = "$jj_names"
  fi

  section "listing after"
  listing "${roots[@]}" >"$scratch/after"
  git -C "$primary" for-each-ref --format='%(refname) %(objectname)' >>"$scratch/after"
  if cmp -s "$scratch/before" "$scratch/after"; then
    pass "refs, admin directories, op heads and every tree's files unchanged ($(wc -l <"$scratch/before") entries)"
  else
    diff "$scratch/before" "$scratch/after" | head -40 | sed 's/^/  /'
    fail "the detector run changed the fixture"
  fi
}

if [[ -n $live ]]; then live_mode; else fixture_mode; fi

section "result"
echo "failures: $failures"
((failures == 0))
