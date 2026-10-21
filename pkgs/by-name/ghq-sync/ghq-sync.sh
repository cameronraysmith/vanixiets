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
  ghq-sync --seed-zoxide [QUERY]    register `ghq list -p [QUERY]` repos with
                                    zoxide, no network access
  ghq-sync --all [QUERY]            operate over `ghq list [QUERY]` (implies -u
                                    when fetching); combinable with --deepen/--full

Targets:
  A TARGET is anything ghq get accepts (a user/project, host/user/project, or
  URL) or a path to a directory inside an already-cloned repository under
  $(ghq root), such as `.`; fetch mode turns such a path into the repository's
  host/user/project before calling ghq get, and --deepen/--full act on it. With
  no positional targets the fetch mode reads targets from stdin, one per line
  (piped straight through to ghq); --deepen/--full likewise read stdin.
  On a host-shared tree (GHQ_SYNC_DELEGATE set) fetch mode refuses a bare
  project name, which ghq would complete with the writer's absent ghq.user;
  name it as owner/repo, host/owner/repo, a URL, or a path such as `.`.

Options:
  --deepen N       Deepen each resolved repo by N commits (git fetch --deepen=N),
                   keeping the blobless partial filter.
  --full           Promote each resolved lazy clone to a full clone in place. A
                   target that is not yet cloned is cloned fully (plain ghq get).
  --seed-zoxide [QUERY]
                   Register every repo in `ghq list -p [QUERY]` with zoxide
                   without any network access, printing one `added: <path>` line
                   per repo. Bulk-seeds the directory index from the local tree.
  --all [QUERY]    Use `ghq list [QUERY]` as the target set. The single optional
                   positional is the ghq list QUERY.
  -u, --update     Pass ghq's -u to update already-cloned repos (fetch mode).
  --tags           On a host-shared tree, also fetch the remote's tags; full clones
                   always fetch tags on update, shallow clones fetch absent tags at
                   depth 1 without moving their history boundary (fetch mode).
  -j, --jobs N     Bounded concurrency for --deepen/--full (default: 6).
  -n, --dry-run    Print intended actions for --deepen/--full/--all/--seed-zoxide;
                   no mutation.
  -h, --help       Show this help and exit.

Fetch mode is a transparent pass-through to `ghq get --shallow --partial blobless
--no-recursive -P [-u]`; ghq's own output and exit status are preserved. The
--deepen and --full modes print exactly one status line per repo (deepened:,
promoted to full:, skip: <reason>, or failed:) and continue past per-repo errors.

Repositories fetched, updated, deepened, or promoted are also registered with
zoxide as a silent side effect; fetch mode stays output-transparent, so
`ghq-sync ... | cb copy` still captures exactly ghq's own output. --seed-zoxide
prints one `added: <path>` line per indexed repo.

Environment:
  GHQ_SYNC_DELEGATE  Executable that carries out --deepen and in-place --full
                     work on a host-shared tree this account cannot write; it
                     is called as `deepen N PATH` or `promote PATH`.
  GHQ_SYNC_NO_ZOXIDE Skip zoxide registration (the shared tree's writer).
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

# An existing directory under $(ghq root) becomes its repository's
# host/owner/project for ghq get; anything else passes through unchanged. A
# submodule's working tree has a .git file, so the walk names its superproject.
# On a host-shared tree a bare name is refused, as the ghq wrapper refuses it.
normalize_target() {
  local target="$1" root dir
  if [ ! -d "$target" ]; then
    if [ -n "${GHQ_SYNC_DELEGATE:-}" ] && [[ "$target" != */* ]]; then
      printf 'ghq: name the repository as owner/repo, host/owner/repo, a URL, or a path (for example .)\n' >&2
      exit 2
    fi
    printf '%s\n' "$target"
    return 0
  fi
  root="$(realpath -m -- "$(ghq root)")"
  dir="$(realpath -- "$target")"
  case "$dir/" in
    "$root"/*/) ;;
    *)
      printf '%s\n' "$target"
      return 0
      ;;
  esac
  while [ "$dir" != "$root" ] && [ ! -d "$dir/.git" ]; do
    dir="$(dirname -- "$dir")"
  done
  if [ "$dir" = "$root" ]; then
    printf '%s\n' "$target"
  else
    printf '%s\n' "${dir#"$root"/}"
  fi
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

register_targets() {
  # Batch-register the on-disk paths of the given targets with zoxide in a single
  # `zoxide add` (its multi-path form), run once after the work completes. The
  # single call both uses the list form and avoids zoxide's lockless
  # read-modify-write lost-update race when deepen/full workers run in parallel.
  # Silent: stdout stays empty so fetch mode's `... | cb copy` pipe is
  # unaffected, and a zoxide failure never aborts ghq-sync.
  if [ "$dry_run" = 1 ] || [ -n "${GHQ_SYNC_NO_ZOXIDE:-}" ]; then return 0; fi
  local target path
  local paths=()
  for target in "$@"; do
    path="$(resolve_repo "$target")"
    if [ -n "$path" ] && [ -d "$path" ]; then paths+=("$path"); fi
  done
  if [ "${#paths[@]}" -gt 0 ]; then
    zoxide add "${paths[@]}" >/dev/null 2>&1 || true
  fi
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
  if [ -n "${GHQ_SYNC_DELEGATE:-}" ]; then
    "$GHQ_SYNC_DELEGATE" deepen "$deepen_n" "$path" || printf 'failed: %s\n' "$path"
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
  if [ -n "${GHQ_SYNC_DELEGATE:-}" ]; then
    "$GHQ_SYNC_DELEGATE" promote "$path" || printf 'failed: %s\n' "$path"
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
tags=0
all=0
dry_run=0
jobs=6
deepen_n=""
targets=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    -u | --update) update=1 ;;
    --tags) tags=1 ;;
    --full) mode=full ;;
    --seed-zoxide) mode=seed ;;
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
if [ "$tags" = 1 ] && { [ "$mode" = deepen ] || [ "$mode" = full ]; }; then
  die "--tags cannot be combined with --deepen or --full"
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
elif [ "$mode" != fetch ] && [ "$mode" != seed ] && [ "${#targets[@]}" -eq 0 ]; then
  mapfile -t targets
fi

case "$mode" in
  fetch)
    if [ "${#targets[@]}" -eq 0 ] && [ "$all" != 1 ] && [ "$dry_run" != 1 ]; then
      mapfile -t targets
    fi
    for i in "${!targets[@]}"; do
      targets[i]="$(normalize_target "${targets[i]}")" || exit 2
    done
    getflags=(get --shallow --partial blobless --no-recursive -P)
    if [ "$update" = 1 ]; then getflags+=(-u); fi
    if [ "$tags" = 1 ]; then
      [ -n "${GHQ_SYNC_DELEGATE:-}" ] || die "--tags needs a host-shared ghq tree; elsewhere run git fetch --tags in the clone"
      getflags+=(--tags)
    fi
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
    # Run ghq (not exec) so each resolved clone path can be registered with
    # zoxide afterward. ghq's stdout/stderr/exit status pass through untouched;
    # resolution uses command substitution and zoxide is silent, so fetch mode's
    # `… | cb copy` pipe still sees exactly ghq's own output.
    if [ "${#targets[@]}" -eq 0 ]; then
      mapfile -t targets
    fi
    rc=0
    ghq "${getflags[@]}" "${targets[@]}" || rc=$?
    register_targets "${targets[@]}"
    exit "$rc"
    ;;
  deepen)
    run_pool deepen_one "${targets[@]}"
    register_targets "${targets[@]}"
    ;;
  full)
    run_pool full_one "${targets[@]}"
    register_targets "${targets[@]}"
    ;;
  seed)
    if [ "${#targets[@]}" -gt 1 ]; then
      die "--seed-zoxide accepts at most one QUERY argument"
    fi
    listargs=(list -p)
    if [ -n "${targets[0]:-}" ]; then listargs+=("${targets[0]}"); fi
    mapfile -t paths < <(ghq "${listargs[@]}")
    if [ "${#paths[@]}" -eq 0 ]; then exit 0; fi
    if [ "$dry_run" = 1 ]; then
      printf 'would add: %s\n' "${paths[@]}"
      exit 0
    fi
    if zoxide add "${paths[@]}" >/dev/null 2>&1; then
      printf 'added: %s\n' "${paths[@]}"
    else
      printf 'failed: %s\n' "${paths[@]}"
    fi
    ;;
esac
