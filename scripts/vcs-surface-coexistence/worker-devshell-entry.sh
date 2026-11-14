#!/usr/bin/env bash
# Task 1.1 of openspec/changes/vcs-surface-coexistence: a working tree created
# the way omnigent's create_worktree does, then devshell entry there, as the
# account running this script.
#
# omnigent/host/git_worktree.py create_worktree, with no base and no selected
# subdirectory, runs `git worktree add -b <branch> <path>` from the main work
# tree, where <path> is <parent>/<repo>-worktrees/<branch with / as ->
# (_resolve_worktree_path), and the branch starts at the main work tree's HEAD.
#
# The scratch clone's primary tree is entered first, so it holds generated
# agent context to compare. Asserted for the new tree: its own AGENTS.md,
# CLAUDE.md and .agents/.context-compile-key with the expected tier,
# core.hooksPath read from the shared config as the absolute common-dir hooks
# path, and a git commit there running the pre-commit and commit-msg hooks and
# gaining a Change-Id trailer. Asserted for the primary tree: its generated
# files, hook programs and core.hooksPath are byte-identical before and after.
#
# --no-user-context runs every step with HOME at an empty scratch home and the
# XDG base directories pinned to the real home's, so git, nix and direnv keep
# their configuration and only $HOME/.claude/CLAUDE.md is absent; the expected
# tier is then `full`, otherwise `default` (modules/devshells/default.nix).
#
# Operator use on magnetite, as an Omnigent worker:
#   ssh magnetite.zt 'sudo -n -u omnigent-cameron -i bash -s -- [--no-user-context]' \
#     <scripts/vcs-surface-coexistence/worker-devshell-entry.sh
# Exit 0 when every assertion holds, 1 otherwise; the FAIL lines say which.
set -euo pipefail

repo_url=https://github.com/cameronraysmith/vanixiets
ref=main
user_context=1
keep=0
while (($#)); do
  case $1 in
    --no-user-context) user_context=0 ;;
    --repo-url) repo_url=$2 && shift ;;
    --ref) ref=$2 && shift ;;
    --keep) keep=1 ;;
    *) echo "usage: $0 [--no-user-context] [--repo-url URL] [--ref REF] [--keep]" >&2 && exit 2 ;;
  esac
  shift
done

scratch=$(mktemp -d "${TMPDIR:-/tmp}/vcs-worker-entry.XXXXXX")
primary=$scratch/vanixiets
branch=vcs-probe/worker-entry
tree=$scratch/vanixiets-worktrees/${branch//\//-}
failures=0

# The fleet's direnvrc keeps each tree's nix-direnv layout under the cache
# directory, keyed by a hash of the tree's path, not in the tree.
layout_dir() { printf '%s/direnv/layouts/%s-%s' "${XDG_CACHE_HOME:-$HOME/.cache}" "$(printf '%s' "$1" | sha256sum | cut -c1-32)" "${1##*/}"; }

cleanup() {
  local t
  for t in "$tree" "$primary"; do
    direnv revoke "$t" >/dev/null 2>&1 || true
  done
  if ((keep)); then
    echo "kept: $scratch"
  else
    for t in "$tree" "$primary"; do
      rm -rf "$(layout_dir "$t")"
    done
    chmod -R u+w "$scratch" 2>/dev/null || true
    rm -rf "$scratch"
  fi
}
trap cleanup EXIT

section() { printf '\n## %s\n' "$*"; }
check() {
  local what=$1
  shift
  if "$@"; then
    echo "PASS: $what"
  else
    echo "FAIL: $what"
    failures=$((failures + 1))
  fi
}

if ((user_context)); then
  expected_tier=default
else
  export XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
  export XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
  export XDG_STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}
  export XDG_CACHE_HOME=${XDG_CACHE_HOME:-$HOME/.cache}
  mkdir -p "$scratch/home"
  export HOME=$scratch/home
  expected_tier=full
fi

section "account"
echo "user=$(id -un) host=$(hostname) HOME=$HOME scratch=$scratch"
for t in git direnv nix jj mergify; do
  printf '%s: %s\n' "$t" "$(command -v "$t" || echo MISSING)"
done
git --version
nix --version
direnv version
ls -l "$HOME/.claude/CLAUDE.md" 2>&1 || true
echo "expected tier: $expected_tier"
check "user-level CLAUDE.md presence matches the run's mode" \
  test "$([[ -e $HOME/.claude/CLAUDE.md ]] && echo 1 || echo 0)" = "$user_context"

# Prints the entry's exit status and stderr; returns 0 so later steps still run.
enter() {
  local dir=$1 label=$2 status=0
  direnv allow "$dir"
  (cd "$dir" && direnv exec "$dir" true) >"$scratch/$label.out" 2>"$scratch/$label.err" || status=$?
  echo "$label entry exit: $status"
  echo "$label entry stderr (direnv progress lines dropped):"
  grep -vE '^direnv: (loading|using|export|nix-direnv: (Using cached|Renewed))' "$scratch/$label.err" | sed 's/^/  /' || true
  return 0
}

# Generated files, hook programs and the shared hook location of one tree.
snapshot() {
  local dir=$1 common f
  common=$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir)
  for f in "$dir/AGENTS.md" "$dir/CLAUDE.md" "$dir"/.agents/.context-*; do
    if [[ -e $f ]]; then
      printf '%s %s %s\n' "$(sha256sum <"$f" | cut -c1-64)" "$([[ -L $f ]] && echo link || echo file)" "${f#"$dir"/}"
    else
      printf 'missing %s\n' "${f#"$dir"/}"
    fi
  done
  while IFS= read -r -d '' f; do
    printf '%s hook %s\n' "$(sha256sum <"$f" | cut -c1-64)" "${f#"$common"/hooks/}"
  done < <(find "$common/hooks" -type f ! -name '*.sample' -print0 | sort -z)
  printf 'core.hooksPath=%s\n' "$(git -C "$dir" config --get core.hooksPath || echo unset)"
}

section "clone $repo_url at $ref"
git clone --quiet --branch "$ref" "$repo_url" "$primary"
git -C "$primary" log -1 --format='%H %cs %s'
common=$(git -C "$primary" rev-parse --path-format=absolute --git-common-dir)

section "devshell entry in the primary tree"
enter "$primary" primary
snapshot "$primary" >"$scratch/primary.before"
cat "$scratch/primary.before"
git -C "$primary" config --local --list >"$scratch/config.before"

section "omnigent-style worktree: git worktree add -b $branch $tree"
mkdir -p "${tree%/*}"
(cd "$primary" && LC_ALL=C git worktree add -b "$branch" "$tree")
git -C "$primary" worktree list --porcelain

section "devshell entry in the new tree"
enter "$tree" tree
snapshot "$tree" | tee "$scratch/tree.after"

section "agent context in the new tree"
key=
[[ -r $tree/.agents/.context-compile-key ]] && read -r key <"$tree/.agents/.context-compile-key"
echo "compile key: ${key:-<none>}"
for f in AGENTS.md CLAUDE.md; do
  check "tree has its own regular $f" test -f "$tree/$f" -a ! -L "$tree/$f"
done
check "compile key names tier $expected_tier" test "${key##* }" = "$expected_tier"
head -c 300 "$tree/AGENTS.md" 2>/dev/null | sed 's/^/  /' || true

section "hook location"
origin=$(git -C "$tree" config --show-origin core.hooksPath || true)
echo "tree:    $origin"
echo "primary: $(git -C "$primary" config --show-origin core.hooksPath || true)"
check "core.hooksPath is the shared config's absolute common-dir hooks path" \
  test "$origin" = "file:$common/config	$common/hooks"
echo "hooks directory:"
for f in "$common"/hooks/*; do
  [[ $f == *.sample ]] && continue
  if [[ -d $f ]]; then
    printf '  %s/: %s\n' "${f##*/}" "$(find "$f" -mindepth 1 -printf '%P ')"
  else
    printf '  %s: %s\n' "${f##*/}" "$(grep -m1 -oE 'prek|mergify|pre-commit' "$f" | head -1 || echo '?')"
  fi
done
echo "shared config changes from worktree creation and entry:"
git -C "$primary" config --local --list >"$scratch/config.after"
diff "$scratch/config.before" "$scratch/config.after" | sed 's/^/  /' || true

section "git commit in the new tree"
echo "probe" >"$tree/vcs-probe.txt"
git -C "$tree" add vcs-probe.txt
commit_status=0
GIT_TRACE=1 git -C "$tree" commit -m "vcs probe: worker commit" >"$scratch/commit.out" 2>"$scratch/commit.err" || commit_status=$?
echo "commit exit: $commit_status"
grep -vE '^[0-9:.]+ (git\.c|run-command\.c|exec-cmd\.c|common-main\.c|trace\.c|read-cache\.c|prompt\.c|setup\.c|compat)' "$scratch/commit.err" | sed 's/^/  /' | tail -20 || true
ran_hook() { grep -qE "start_command: [^ ]*/hooks/$1( |\$)" "$scratch/commit.err"; }
hooks_run=$(grep -oE "start_command: [^ ]*/hooks/[a-z-]+( |$)" "$scratch/commit.err" | sed 's/.*hooks\///' | sort -u | tr -d ' ' | tr '\n' ' ' || true)
echo "hooks run: ${hooks_run:-none}"
check "commit succeeded" test "$commit_status" = 0
check "pre-commit hook ran" ran_hook pre-commit
check "commit-msg hook ran" ran_hook commit-msg
git -C "$tree" log -1 --format=%B | sed 's/^/  /'
has_change_id() { git -C "$tree" log -1 --format=%B | grep -qE '^Change-Id: I[0-9a-f]{40}$'; }
check "commit carries a Change-Id trailer" has_change_id

section "primary tree after"
snapshot "$primary" >"$scratch/primary.after"
diff "$scratch/primary.before" "$scratch/primary.after" | sed 's/^/  /' || true
check "primary tree's generated files, hooks and core.hooksPath unchanged" \
  cmp -s "$scratch/primary.before" "$scratch/primary.after"

section "result"
echo "failures: $failures"
((failures == 0))
