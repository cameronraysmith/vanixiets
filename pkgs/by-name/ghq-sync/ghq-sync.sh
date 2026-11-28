#!/usr/bin/env bash
# shellcheck shell=bash

usage() {
  cat <<'USAGE'
ghq-sync - lazy, partial-clone-aware ghq wrapper for the Category-2 reference
tree. Fetches repositories as shallow blobless clones, updates them, deepens
their history in place, promotes lazy clones to full clones, and hydrates the
blobs a revision needs, on demand.

Usage:
  ghq-sync [TARGET...]              lazy fetch (shallow + blobless + no-recursive)
  ghq-sync -u|--update [TARGET...]  lazy fetch, then ghq's native update per repo
  ghq-sync --deepen N [TARGET...]   deepen history by N commits in place
  ghq-sync --full [TARGET...]       promote a lazy clone to a full clone in place
  ghq-sync --hydrate REV [TARGET...]
                                    fetch every object REV's tree needs that the
                                    partial clone lacks
  ghq-sync --seed-zoxide [QUERY]    register `ghq list -p [QUERY]` repos with
                                    zoxide, no network access
  ghq-sync --all [QUERY]            operate over `ghq list [QUERY]` (implies -u
                                    when fetching); combinable with --deepen/--full
  ghq-sync --audit [QUERY]          read-only: compare `ghq list [QUERY]` with
                                    GitHub and print the commands to fix drift

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
                   keeping the blobless partial filter. git marks the commits N
                   below each shallow boundary as new boundaries even when the
                   clone holds their history, so a sized N can hide history the
                   clone held. --deepen 1000000 reaches the roots below the
                   boundaries of the branches it fetches and hides none; a
                   boundary on a tag's commit no fetched branch reaches can
                   remain, and hides nothing. It is the repair an update names
                   when a commit the clone holds without its history lies
                   between the local branch and upstream's ("shallow boundary
                   between the local branch and upstream's"); run -u after it.
                   If -u then fails without that line, upstream rewrote its
                   branch and the boundary was not the cause. If the line
                   still appears after a deepen that printed "deepened:
                   <path>", the history runs deeper than the deepen reaches,
                   and --full repairs it; after one that printed "failed:
                   <path>", the deepen did not run to its end (see the lock
                   below), and the line says nothing of the depth. The deepen
                   fetches the commits and trees of the whole history below
                   those boundaries, which on a large copy can take long,
                   within the writer's limit of one hour per command. A deepen
                   that limit stops normally leaves the clone's history as it
                   was and can be rerun, starting over; if git had to be
                   killed it can leave .git/shallow.lock, after which each
                   deepen of that copy prints only "failed: <path>" and a tag
                   fetch at depth 1 fails with git's "Unable to create
                   '<path>/.git/shallow.lock': File exists.", until the tree's
                   administrator removes the file once no git runs there.
                   --full is the other repair that hides nothing, at the cost
                   of every blob and a full clone.
  --full           Promote each resolved lazy clone to a full clone in place. A
                   target that is not yet cloned is cloned fully (plain ghq get).
  --hydrate REV    Make every blob and tree of REV's tree present in each
                   resolved partial clone, keeping its filter and depth, so that
                   `git show REV:PATH` and checkouts of REV need no lazy fetch.
                   REV is a ref or object name, optionally with ~N or ^N, and its
                   commit must already be in the clone (fetch tags with -u --tags).
                   A diff reads both sides: `git show REV` needs REV and each of
                   its parents hydrated (REV^1, and REV^2 for a merge), and
                   `git diff A B` needs A and B. On a host-shared tree the writer
                   already does this for the commits an update, deepen or tag
                   fetch brings into a clone's branches and remote-tracking
                   branches, merges included, or at the clone's next update or
                   deepen for a request that stops after its fetch, but not for
                   a commit only a tag reaches, as --tags fetches one at depth
                   1, which needs --hydrate TAG until a branch reaches it;
                   readers' git there refuses every transport, so a read
                   needing absent contents fails with "transport '<scheme>' not
                   allowed" and "could not fetch <oid> from promisor remote".
  --seed-zoxide [QUERY]
                   Register every repo in `ghq list -p [QUERY]` with zoxide
                   without any network access, printing one `added: <path>` line
                   per repo. Bulk-seeds the directory index from the local tree.
  --audit [QUERY]  Read-only. Ask GitHub, with this account's `gh` token, about
                   every github.com repo in `ghq list [QUERY]` (batched GraphQL,
                   which follows renames and transfers) and print one line per
                   finding: `renamed:` (with the commands that retire the old
                   path when the new one is cloned, or relocate it otherwise),
                   `case:` (letter case differs only), `missing:` (deleted or
                   private upstream; keep it), `archived:`, and `default branch:`
                   (the clone follows another branch than upstream's default;
                   `ghq-sync -u` follows it). The commands are text for an
                   administrator to run as the tree's writer; the audit itself
                   changes nothing. Without `gh` or a token it says so and exits 0.
  --all [QUERY]    Use `ghq list [QUERY]` as the target set. The single optional
                   positional is the ghq list QUERY.
  -u, --update     Pass ghq's -u to update already-cloned repos (fetch mode).
  --tags           On a host-shared tree, also fetch the remote's tags; full clones
                   always fetch tags on update, shallow clones fetch absent tags at
                   depth 1 without moving their history boundary, and each such
                   tag commit stays unhydrated until --hydrate TAG or until an
                   update brings in a branch commit that reaches it (fetch mode).
  -j, --jobs N     Bounded concurrency for --deepen/--full/--hydrate (default: 6).
  -n, --dry-run    Print intended actions for --deepen/--full/--hydrate/--all/
                   --seed-zoxide; no mutation.
  -h, --help       Show this help and exit.

Fetch mode is a transparent pass-through to `ghq get --shallow --partial blobless
--no-recursive -P [-u]`; ghq's own output and exit status are preserved. The
--deepen, --full and --hydrate modes print exactly one status line per repo
(deepened:, promoted to full:, hydrated:, skip: <reason>, or failed:) and
continue past per-repo errors.

Repositories fetched, updated, deepened, promoted, or hydrated are also
registered with zoxide as a silent side effect; fetch mode stays
output-transparent, so `ghq-sync ... | cb copy` still captures exactly ghq's own
output. --seed-zoxide prints one `added: <path>` line per indexed repo.

Environment:
  GHQ_SYNC_DELEGATE  Executable that carries out --deepen, in-place --full and
                     --hydrate work on a host-shared tree this account cannot
                     write; it is called as `deepen N PATH`, `promote PATH` or
                     `hydrate REV PATH`.
  GHQ_SYNC_NO_ZOXIDE Skip zoxide registration (the shared tree's writer).
  gh                 --audit runs the `gh` on PATH, with its stored token.
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

# Ref or object name, optionally with ~N or ^N; no ranges, reflogs or options.
# The writer's request handler applies the same rule.
is_revision() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._/+-]*([~^][0-9]*)*$ ]] && [[ "$1" != *..* ]]
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

hydrate_one() {
  local target="$1" path tree listed line before="" count=0
  local missing=()
  path="$(resolve_repo "$target")"
  if [ -z "$path" ]; then
    printf 'skip: %s (not cloned)\n' "$target"
    return 0
  fi
  if [ "$dry_run" = 1 ]; then
    printf 'would hydrate %s: %s\n' "$hydrate_rev" "$path"
    return 0
  fi
  if [ -n "${GHQ_SYNC_DELEGATE:-}" ]; then
    "$GHQ_SYNC_DELEGATE" hydrate "$hydrate_rev" "$path" || printf 'failed: %s\n' "$path"
    return 0
  fi
  # GIT_NO_LAZY_FETCH keeps every probe local: a lazy fetch would fetch objects
  # one by one, and would make an absent revision look present.
  if ! GIT_NO_LAZY_FETCH=1 git -C "$path" rev-parse --verify --quiet --end-of-options "$hydrate_rev^{commit}" >/dev/null 2>&1 \
    || ! tree="$(GIT_NO_LAZY_FETCH=1 git -C "$path" log -1 --no-walk --format=%T --end-of-options "$hydrate_rev^{commit}" 2>/dev/null)" \
    || [ -z "$tree" ]; then
    printf 'skip: %s (%s is not a commit in this clone; fetch it first, for example with ghq-sync -u --tags)\n' "$path" "$hydrate_rev"
    return 0
  fi
  # Each pass fetches, in one request, every object the walk found missing; a
  # tree that arrives can reveal further missing objects beneath it, and the
  # walk cannot start until the root tree itself is present. The same objects
  # missing twice means the remote did not send them.
  while :; do
    if ! GIT_NO_LAZY_FETCH=1 git -C "$path" cat-file -e "$tree" 2>/dev/null; then
      listed="?$tree"
    elif ! listed="$(GIT_NO_LAZY_FETCH=1 git -C "$path" rev-list --objects --no-object-names --missing=print "$tree" 2>/dev/null)"; then
      printf 'failed: %s\n' "$path"
      return 0
    fi
    missing=()
    while IFS= read -r line; do
      case "$line" in
        '?'*) missing+=("${line#\?}") ;;
      esac
    done <<<"$listed"
    if [ "${#missing[@]}" -eq 0 ]; then
      break
    fi
    if [ "${missing[*]}" = "$before" ] \
      || ! printf '%s\n' "${missing[@]}" | git -C "$path" -c fetch.negotiationAlgorithm=noop fetch \
        --no-tags --no-write-fetch-head --recurse-submodules=no --filter=blob:none --stdin origin >/dev/null 2>&1; then
      printf 'failed: %s\n' "$path"
      return 0
    fi
    before="${missing[*]}"
    count=$((count + ${#missing[@]}))
  done
  printf 'hydrated: %s (%s, %s objects fetched)\n' "$path" "$hydrate_rev" "$count"
  return 0
}

# The branch a clone follows: a single-branch clone's one fetched branch, or the
# branch origin/HEAD names in a clone that fetches every branch.
followed_branch() {
  local path="$1" refspecs head
  mapfile -t refspecs < <(git -C "$path" --no-optional-locks config --get-all remote.origin.fetch 2>/dev/null || true)
  if [ "${#refspecs[@]}" -eq 1 ] && [[ "${refspecs[0]}" =~ ^\+?refs/heads/([^*:]+):refs/remotes/origin/([^*:]+)$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  if head="$(git -C "$path" --no-optional-locks symbolic-ref --short -q refs/remotes/origin/HEAD 2>/dev/null)"; then
    printf '%s\n' "${head#origin/}"
  fi
}

# Print one command line, each word shell-quoted, indented under its finding.
show_command() {
  local quoted
  printf -v quoted ' %q' "$@"
  printf '   %s\n' "${quoted# }"
}

audit_one() {
  local name="$1" info="$2" path="$root/$1" canonical archived upstream followed old_owner new_path findings=0
  if [ "$info" = null ]; then
    printf 'missing: %s (deleted or private upstream; keep it, it may be the only copy)\n' "$name"
    return 1
  fi
  canonical="github.com/$(jq -r .nameWithOwner <<<"$info")"
  archived="$(jq -r .isArchived <<<"$info")"
  upstream="$(jq -r '.defaultBranchRef.name // empty' <<<"$info")"
  if [ "$canonical" != "$name" ] && [ "${canonical,,}" = "${name,,}" ]; then
    printf 'case: %s is %s upstream (letter case only; a case-sensitive filesystem would hold a second clone for the other spelling)\n' "$name" "$canonical"
    findings=1
  elif [ "$canonical" != "$name" ]; then
    findings=1
    old_owner="$root/${name%/*}"
    new_path="$root/$canonical"
    if [ -d "$new_path/.git" ]; then
      printf 'renamed: %s -> %s (the new path is already cloned; retire the old one)\n' "$name" "$canonical"
      show_command sudo -u "$writer" mv -- "$path" "$old_owner/.retired-${name##*/}"
      show_command sudo -u "$writer" rm -rf -- "$old_owner/.retired-${name##*/}"
    else
      printf 'renamed: %s -> %s (relocate the clone without fetching it again)\n' "$name" "$canonical"
      show_command sudo -u "$writer" mkdir -p -m 0750 -- "${new_path%/*}"
      show_command sudo -u "$writer" mv -n -- "$path" "$new_path"
      show_command sudo -u "$writer" env -i HOME=/var/empty GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
        "$(command -v git)" -C "$new_path" remote set-url origin "https://$canonical"
      show_command ghq-sync -u "$canonical"
    fi
    show_command sudo -u "$writer" rmdir -- "$old_owner"
    show_command zoxide remove "$path"
  fi
  if [ "$archived" = true ]; then
    printf 'archived: %s (upstream is read-only; it will not change)\n' "$name"
    findings=1
  fi
  followed="$(followed_branch "$path")"
  if [ -n "$upstream" ] && [ -n "$followed" ] && [ "$followed" != "$upstream" ]; then
    printf 'default branch: %s follows %s, upstream default is %s (ghq-sync -u %s follows it)\n' \
      "$name" "$followed" "$upstream" "$name"
    findings=1
  fi
  # Non-zero when anything was reported, so the caller can count findings.
  [ "$findings" -eq 0 ]
}

# Read-only: ask GitHub about every github.com repository in `ghq list [QUERY]`,
# fifty to a GraphQL request, and report drift with the commands that resolve it.
# git cannot see a rename, since GitHub's git endpoint answers the old name; the
# API's repository() follows renames and transfers.
audit() {
  local query="$1" names=() name listargs=(list) i j q owner repo reply info checked=0 found=0 root writer
  if ! command -v gh >/dev/null 2>&1 || ! gh auth token >/dev/null 2>&1; then
    printf 'audit: no GitHub token (install gh and run: gh auth login); nothing was checked\n' >&2
    return 0
  fi
  root="$(realpath -m -- "$(ghq root)")"
  writer="$(stat -c %U -- "$root")"
  if [ -n "$query" ]; then listargs+=("$query"); fi
  while IFS= read -r name; do
    if [[ "$name" =~ ^github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
      names+=("$name")
    else
      printf 'skip: %s (not a github.com owner/name)\n' "$name"
    fi
  done < <(ghq "${listargs[@]}")
  for ((i = 0; i < ${#names[@]}; i += 50)); do
    q='query{'
    for ((j = i; j < i + 50 && j < ${#names[@]}; j++)); do
      owner="${names[j]#github.com/}"
      repo="${owner#*/}"
      owner="${owner%%/*}"
      q+="r$j:repository(owner:\"$owner\",name:\"$repo\"){nameWithOwner isArchived defaultBranchRef{name}} "
    done
    q+='}'
    # A repository that is gone answers null with an error beside the others'
    # data, and gh then exits non-zero; the data is still read.
    reply="$(gh api graphql -f query="$q" 2>/dev/null)" || true
    if ! jq -e '.data | type == "object"' >/dev/null 2>&1 <<<"$reply"; then
      printf 'failed: the GitHub query for %s repositories starting at %s\n' "$((j - i))" "${names[i]}"
      continue
    fi
    for ((j = i; j < i + 50 && j < ${#names[@]}; j++)); do
      info="$(jq -c --arg k "r$j" '.data[$k]' <<<"$reply")"
      checked=$((checked + 1))
      audit_one "${names[j]}" "$info" || found=$((found + 1))
    done
  done
  printf 'audit: %s repositories checked, %s with findings; nothing was changed\n' "$checked" "$found"
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
hydrate_rev=""
targets=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    -u | --update) update=1 ;;
    --tags) tags=1 ;;
    --full) mode=full ;;
    --seed-zoxide) mode=seed ;;
    --audit) mode=audit ;;
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
    --hydrate=*)
      mode=hydrate
      hydrate_rev="${1#*=}"
      ;;
    --hydrate)
      if [ "$#" -lt 2 ]; then die "--hydrate requires a revision"; fi
      shift
      mode=hydrate
      hydrate_rev="$1"
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
if [ "$mode" = hydrate ] && ! is_revision "$hydrate_rev"; then
  die "--hydrate requires a ref or object name, optionally with ~N or ^N: $hydrate_rev"
fi
if [ "$mode" = audit ] && { [ "$tags" = 1 ] || [ "$update" = 1 ] || [ "$all" = 1 ] || [ "$dry_run" = 1 ]; }; then
  die "--audit is read-only and takes only an optional QUERY"
fi
if [ "$tags" = 1 ] && { [ "$mode" = deepen ] || [ "$mode" = full ] || [ "$mode" = hydrate ]; }; then
  die "--tags cannot be combined with --deepen, --full or --hydrate"
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
elif [ "$mode" != fetch ] && [ "$mode" != seed ] && [ "$mode" != audit ] && [ "${#targets[@]}" -eq 0 ]; then
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
  hydrate)
    run_pool hydrate_one "${targets[@]}"
    register_targets "${targets[@]}"
    ;;
  audit)
    if [ "${#targets[@]}" -gt 1 ]; then
      die "--audit accepts at most one QUERY argument"
    fi
    audit "${targets[0]:-}"
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
