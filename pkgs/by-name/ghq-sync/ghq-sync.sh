#!/usr/bin/env bash
# shellcheck shell=bash

usage() {
  cat <<'USAGE'
ghq-sync - lazy, partial-clone-aware ghq wrapper for the Category-2 reference
tree. Fetches repositories as shallow blobless clones, updates them, deepens
their history in place, and promotes lazy clones to full clones on demand.

Usage:
  ghq-sync [TARGET...]              lazy fetch (shallow + blobless + no-recursive)
  ghq-sync -u|--update [TARGET...]  lazy fetch, then ghq's native update per repo
  ghq-sync --deepen N [TARGET...]   deepen history by N commits in place
  ghq-sync --full [TARGET...]       promote a lazy clone to a full clone in place
  ghq-sync --all [QUERY]            operate over `ghq list [QUERY]` (implies -u
                                    when fetching); combinable with --deepen/--full

Targets:
  A TARGET is anything ghq get accepts (a user/project, host/user/project, or
  URL) or, for --deepen/--full, a path to an already-cloned local git repo. With
  no positional targets the fetch mode reads targets from stdin, one per line
  (piped straight through to ghq); --deepen/--full likewise read stdin.

Options:
  --deepen N       Deepen each resolved repo by N commits (git fetch --deepen=N),
                   keeping the blobless partial filter.
  --full           Promote each resolved lazy clone to a full clone in place. A
                   target that is not yet cloned is cloned fully (plain ghq get).
  --all [QUERY]    Use `ghq list [QUERY]` as the target set. The single optional
                   positional is the ghq list QUERY.
  -u, --update     Pass ghq's -u to update already-cloned repos (fetch mode).
  -j, --jobs N     Bounded concurrency for --deepen/--full (default: 6).
  -n, --dry-run    Print intended actions for --deepen/--full/--all; no mutation.
  -h, --help       Show this help and exit.

Fetch mode is a transparent pass-through to `ghq get --shallow --partial blobless
--no-recursive -P [-u]`; ghq's own output and exit status are preserved. The
--deepen and --full modes print exactly one status line per repo (deepened:,
promoted to full:, skip: <reason>, or failed:) and continue past per-repo errors.
USAGE
}

die() {
  printf 'error: %s\n\n' "$1" >&2
  usage >&2
  exit 2
}

is_pos_int() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

resolve_repo() {
  local target="$1" top path
  if [ -d "$target" ] && top="$(git -C "$target" rev-parse --show-toplevel 2>/dev/null)"; then
    printf '%s\n' "$top"
    return 0
  fi
  path="$(ghq list -p -e "$target" 2>/dev/null | head -n1)" || true
  if [ -n "$path" ]; then
    printf '%s\n' "$path"
  fi
  return 0
}

deepen_one() {
  local target="$1" path
  path="$(resolve_repo "$target")"
  if [ -z "$path" ]; then
    printf 'skip: %s (not cloned)\n' "$target"
    return 0
  fi
  if [ "$dry_run" = 1 ]; then
    printf 'would deepen by %s: %s\n' "$deepen_n" "$path"
    return 0
  fi
  if git -C "$path" fetch --deepen="$deepen_n" >/dev/null 2>&1; then
    printf 'deepened: %s\n' "$path"
  else
    printf 'failed: %s\n' "$path"
  fi
  return 0
}

promote_inplace() {
  local path="$1" up shallow
  git -C "$path" config --replace-all remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*' >/dev/null 2>&1 || return 1
  shallow="$(git -C "$path" rev-parse --is-shallow-repository 2>/dev/null)"
  # --unshallow errors on a non-shallow repo, so branch on the shallow flag. On a
  # previously-deepened repo this fetch re-applies the blobless filter, so the
  # filter is cleared *after* it and *before* --refetch, or blobs never backfill.
  if [ "$shallow" = true ]; then
    git -C "$path" fetch --unshallow origin >/dev/null 2>&1 || return 1
  else
    git -C "$path" fetch origin >/dev/null 2>&1 || return 1
  fi
  # An absent key makes `git config --unset-all` exit 5; tolerate it.
  git -C "$path" config --unset-all remote.origin.partialclonefilter >/dev/null 2>&1 || true
  # --refetch (git >= 2.36) with no filter configured backfills every blob across
  # full history; it must run after the filter is unset above.
  git -C "$path" fetch --refetch origin >/dev/null 2>&1 || return 1
  # promisor is unset only after the backfill: dropping it earlier makes the
  # unshallow/refetch abort on still-missing promisor objects (git exits 128).
  git -C "$path" config --unset-all remote.origin.promisor >/dev/null 2>&1 || true
  git -C "$path" config --unset-all remote.origin.partialclonefilter >/dev/null 2>&1 || true
  git -C "$path" gc --quiet >/dev/null 2>&1 || true
  if up="$(git -C "$path" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)"; then
    git -C "$path" merge --ff-only "$up" >/dev/null 2>&1 || true
  fi
  git -C "$path" submodule update --init --recursive >/dev/null 2>&1 || true
  return 0
}

full_one() {
  local target="$1" path
  path="$(resolve_repo "$target")"
  if [ -z "$path" ]; then
    if [ "$dry_run" = 1 ]; then
      printf 'would clone (full): %s\n' "$target"
      return 0
    fi
    if ghq get "$target" >/dev/null 2>&1; then
      printf 'promoted to full: %s\n' "$target"
    else
      printf 'failed: %s\n' "$target"
    fi
    return 0
  fi
  if [ "$dry_run" = 1 ]; then
    printf 'would promote to full: %s\n' "$path"
    return 0
  fi
  if promote_inplace "$path"; then
    printf 'promoted to full: %s\n' "$path"
  else
    printf 'failed: %s\n' "$path"
  fi
  return 0
}

run_pool() {
  local worker="$1"
  shift
  local target
  for target in "$@"; do
    "$worker" "$target" &
    while [ "$(jobs -rp | wc -l)" -ge "$jobs" ]; do
      wait -n 2>/dev/null || true
    done
  done
  wait
}

mode=fetch
update=0
all=0
dry_run=0
jobs=6
deepen_n=""
targets=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    -u | --update) update=1 ;;
    --full) mode=full ;;
    --all) all=1 ;;
    -n | --dry-run) dry_run=1 ;;
    --deepen=*)
      mode=deepen
      deepen_n="${1#*=}"
      ;;
    --deepen)
      if [ "$#" -lt 2 ]; then die "--deepen requires a value"; fi
      shift
      mode=deepen
      deepen_n="$1"
      ;;
    -j=* | --jobs=*) jobs="${1#*=}" ;;
    -j | --jobs)
      if [ "$#" -lt 2 ]; then die "--jobs requires a value"; fi
      shift
      jobs="$1"
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*) die "unknown option: $1" ;;
    *) targets+=("$1") ;;
  esac
  shift
done

while [ "$#" -gt 0 ]; do
  targets+=("$1")
  shift
done

if ! is_pos_int "$jobs"; then
  die "--jobs must be a positive integer: $jobs"
fi
if [ "$mode" = deepen ] && ! is_pos_int "$deepen_n"; then
  die "--deepen requires a positive integer: $deepen_n"
fi

if [ "$all" = 1 ]; then
  if [ "${#targets[@]}" -gt 1 ]; then
    die "--all accepts at most one QUERY argument"
  fi
  query="${targets[0]:-}"
  if [ -n "$query" ]; then
    mapfile -t targets < <(ghq list "$query")
  else
    mapfile -t targets < <(ghq list)
  fi
  if [ "$mode" = fetch ]; then update=1; fi
elif [ "$mode" != fetch ] && [ "${#targets[@]}" -eq 0 ]; then
  mapfile -t targets
fi

case "$mode" in
  fetch)
    getflags=(get --shallow --partial blobless --no-recursive -P)
    if [ "$update" = 1 ]; then getflags+=(-u); fi
    if [ "$all" = 1 ] && [ "${#targets[@]}" -eq 0 ]; then
      exit 0
    fi
    if [ "$dry_run" = 1 ]; then
      if [ "${#targets[@]}" -gt 0 ]; then
        printf 'would run: ghq %s %s\n' "${getflags[*]}" "${targets[*]}"
      else
        printf 'would run: ghq %s (targets from stdin)\n' "${getflags[*]}"
      fi
      exit 0
    fi
    exec ghq "${getflags[@]}" "${targets[@]}"
    ;;
  deepen)
    run_pool deepen_one "${targets[@]}"
    ;;
  full)
    run_pool full_one "${targets[@]}"
    ;;
esac
