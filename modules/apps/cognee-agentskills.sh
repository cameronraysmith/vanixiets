#!/usr/bin/env bash
# shellcheck shell=bash
#
# manage the cognee SaaS `agentskills` reference-knowledge dataset.
#
# the corpus is every skill `.md` under
# modules/home/ai/plugins/<group>/.apm/skills/<skill>/ (recursively), plus the
# modules/home/tools/agents-md.nix generator that names many of those skills.
# each source doc is staged into a flat temp dir under a deterministic name
# `<group>__<skill>__<relpath-with-/-as-__>.md`, prefixed with a one-line
# provenance header, then handed to the ambient `cognee` wrapper.
#
# the ambient `cognee` on PATH is the home-manager wrapper: it bakes --api-url
# and reads the sops-provisioned key, so every cognee call here is a bare,
# non-interactive invocation. the dataset uuid is resolved at runtime from
# `cognee datasets list`; it is never hard-coded.
#
# verbs: refresh (full-graph rebuild or scoped forget+re-add), remove (scoped
# forget, no re-add), add (ingest explicit paths), list, status. all deletion
# is targeted (`cognee forget --dataset-id <uuid> --data-id <id>`) except the
# full `refresh --scope all`, which deliberately wipes with `cognee delete -d
# <name> -f` before a clean rebuild.

set -euo pipefail

DATASET="agentskills"
SCOPE="all"
SCOPE_GROUP=""
SCOPE_SKILL=""
DRY_RUN=false
YES=false
VERB=""
declare -a PATHS=()
declare -a CLEANUP_DIRS=()
STAGED_COUNT=0

usage() {
  cat <<'EOF'
cognee-agentskills — manage the cognee SaaS `agentskills` reference dataset.

USAGE:
  cognee-agentskills [FLAGS] <verb> [ARGS]

VERBS:
  refresh                       full-graph rebuild (default --scope all): wipe
                                the dataset, re-stage every in-scope doc + the
                                agents-md.nix special doc, re-ingest, cognify.
  refresh --skill <group>/<skill>
  refresh --plugin <group>      targeted forget of the scope's current items,
                                then re-stage + re-ingest that scope.
  remove  --skill <group>/<skill> | --plugin <group>
                                targeted forget of a scope's items; no re-add.
  add <path>...                 ingest specific in-scope skill .md files (or the
                                agents-md.nix special doc).
  list [--all | --skill G/S | --plugin G]
                                print Name + data_id for the scope (default all).
  status                        print item count and dataset processing status.

FLAGS:
  --dataset NAME   target dataset (default: agentskills)
  --scope SPEC     all | <group> | <group>/<skill>
  --skill  G/S     scope to one skill
  --plugin G       scope to one plugin group
  --all            scope to everything
  --dry-run        print mutating cognee commands instead of running them
  -y, --yes        skip interactive confirmation
  -h, --help       show this help
EOF
}

log() { printf '%s\n' "$*" >&2; }
die() {
  printf 'error: %s\n' "$*" >&2
  exit "${2:-1}"
}

register_cleanup() { CLEANUP_DIRS+=("$1"); }
cleanup() {
  local d
  for d in "${CLEANUP_DIRS[@]:-}"; do
    [[ -n "$d" && -d "$d" ]] && rm -rf "$d"
  done
}
trap cleanup EXIT

# gated executor: prints (quoted) instead of running mutating commands under
# --dry-run. reads never go through run() — they always execute.
run() {
  if [[ "$DRY_RUN" == true ]]; then
    printf '[dry-run] '
    printf '%q ' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

# fails closed: aborts unless the user types an affirmative on the controlling
# tty, or --yes / --dry-run is set.
confirm() {
  local prompt="${1:-Proceed?}" reply
  if [[ "$YES" == true || "$DRY_RUN" == true ]]; then
    return 0
  fi
  if [[ ! -r /dev/tty ]]; then
    die "no controlling tty for confirmation; pass --yes to proceed non-interactively"
  fi
  printf '%s [y/N] ' "$prompt" >/dev/tty
  read -r reply </dev/tty || {
    printf '\n' >&2
    die "aborted"
  }
  case "$reply" in
    y | Y | yes | YES) return 0 ;;
    *) die "aborted" ;;
  esac
}

set_scope_skill() {
  local s="$1"
  [[ "$s" == */* ]] || die "--skill expects <group>/<skill>, got '$s'" 2
  SCOPE=skill
  SCOPE_GROUP="${s%%/*}"
  SCOPE_SKILL="${s#*/}"
}
set_scope_plugin() {
  SCOPE=plugin
  SCOPE_GROUP="$1"
  SCOPE_SKILL=""
}
set_scope() {
  local s="$1"
  if [[ "$s" == "all" ]]; then
    SCOPE=all
  elif [[ "$s" == */* ]]; then
    set_scope_skill "$s"
  else
    set_scope_plugin "$s"
  fi
}

scope_desc() {
  case "$SCOPE" in
    all) printf 'all' ;;
    plugin) printf 'plugin %s' "$SCOPE_GROUP" ;;
    skill) printf 'skill %s/%s' "$SCOPE_GROUP" "$SCOPE_SKILL" ;;
  esac
}

# Name prefix identifying a scope's items in the remote dataset. Only defined
# for plugin/skill scopes; the agents-md special doc has no group prefix and so
# belongs only to the full (all-scope) rebuild.
scope_prefix() {
  case "$SCOPE" in
    skill) printf '%s__%s__' "$SCOPE_GROUP" "$SCOPE_SKILL" ;;
    plugin) printf '%s__' "$SCOPE_GROUP" ;;
    *) die "scope_prefix undefined for scope '$SCOPE'" ;;
  esac
}

# --- source-file enumeration -------------------------------------------------
# fd's default hidden-file skipping never sees `.apm` because each search root
# is the `.apm/skills` directory itself; entries below it are non-hidden.

enum_skill_files() {
  local root="$PLUGINS_ROOT/$1/.apm/skills/$2"
  [[ -d "$root" ]] || return 0
  fd -e md -t f . "$root" --exclude apm_modules --exclude .lake --exclude .DS_Store
}
enum_plugin_files() {
  local root="$PLUGINS_ROOT/$1/.apm/skills"
  [[ -d "$root" ]] || return 0
  fd -e md -t f . "$root" --exclude apm_modules --exclude .lake --exclude .DS_Store
}
enum_all_files() {
  local d
  for d in "$PLUGINS_ROOT"/*/.apm/skills; do
    [[ -d "$d" ]] || continue
    fd -e md -t f . "$d" --exclude apm_modules --exclude .lake --exclude .DS_Store
  done
}
scope_source_files() {
  case "$SCOPE" in
    all) enum_all_files ;;
    plugin) enum_plugin_files "$SCOPE_GROUP" ;;
    skill) enum_skill_files "$SCOPE_GROUP" "$SCOPE_SKILL" ;;
  esac
}

# --- naming ------------------------------------------------------------------

is_special_doc() { [[ "$1" == "$REPO_ROOT/modules/home/tools/agents-md.nix" ]]; }

staged_basename() {
  local src="$1"
  if is_special_doc "$src"; then
    printf 'modules-home-tools__agents-md.nix.md'
    return 0
  fi
  local rel="${src#"$PLUGINS_ROOT"/}"
  local group="${rel%%/*}"
  local rest="${rel#*/.apm/skills/}"
  [[ "$rest" != "$rel" ]] || die "not an in-scope skills path: $src"
  local skill="${rest%%/*}"
  local relpath="${rest#*/}"
  printf '%s__%s__%s' "$group" "$skill" "${relpath//\//__}"
}

item_name() {
  local b
  b="$(staged_basename "$1")"
  printf '%s' "${b%.md}"
}

items_for_skill() {
  local f
  enum_skill_files "$1" "$2" | while IFS= read -r f; do
    item_name "$f"
    printf '\n'
  done
}
items_for_plugin() {
  local f
  enum_plugin_files "$1" | while IFS= read -r f; do
    item_name "$f"
    printf '\n'
  done
}

# backticks in the provenance prose are literal markdown emphasis, not command
# substitution — the surrounding single quotes are deliberate.
# shellcheck disable=SC2016
provenance_line() {
  local src="$1"
  if is_special_doc "$src"; then
    printf 'Source: the `modules/home/tools/agents-md.nix` nix module from the vanixiets repo — the single generator of the AI-agent global config files (~/.claude/CLAUDE.md, ~/.gemini/GEMINI.md, AGENTS.md, CRUSH.md, OPENCODE.md); it references many of the skills in this dataset by name.\n'
    return 0
  fi
  local rel="${src#"$PLUGINS_ROOT"/}"
  local group="${rel%%/*}"
  local rest="${rel#*/.apm/skills/}"
  local skill="${rest%%/*}"
  local relpath="${rest#*/}"
  printf 'Source: the `%s` file of the `%s` skill in the `%s` plugin collection (%s).\n' \
    "$relpath" "$skill" "$group" "$src"
}

stage_file() {
  local src="$1" stagedir="$2" dest
  dest="$stagedir/$(staged_basename "$src")"
  {
    provenance_line "$src"
    printf '\n'
    cat "$src"
  } >"$dest"
}

# stages the current scope's source docs into $1; sets STAGED_COUNT; aborts if
# the enumeration is empty (never treat "no matches" as a wildcard).
stage_scope() {
  local stagedir="$1" f
  STAGED_COUNT=0
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    stage_file "$f" "$stagedir"
    STAGED_COUNT=$((STAGED_COUNT + 1))
  done < <(scope_source_files)
  if ((STAGED_COUNT == 0)); then
    die "no in-scope source files for scope '$(scope_desc)'; refusing to proceed (empty is not a wildcard)"
  fi
}

stage_special_doc() {
  local stagedir="$1" special="$REPO_ROOT/modules/home/tools/agents-md.nix"
  [[ -f "$special" ]] || die "special doc not found: $special"
  stage_file "$special" "$stagedir"
}

# --- remote (cognee) reads ---------------------------------------------------

resolve_uuid() {
  local name="$1" uuid
  uuid="$(cognee datasets list | awk -v n="$name" \
    'length($1)==36 && $1 ~ /^[0-9a-fA-F-]+$/ && $2==n { print $1; exit }')"
  [[ -n "$uuid" ]] || die "dataset '$name' not found in 'cognee datasets list'"
  printf '%s' "$uuid"
}

# emits "data_id<TAB>Name" for each data row of the dataset.
remote_rows() {
  cognee datasets data "$1" | awk \
    'length($1)==36 && $1 ~ /^[0-9a-fA-F-]+$/ { print $1 "\t" $2 }'
}

remote_data_ids() {
  local uuid="$1" prefix="$2"
  remote_rows "$uuid" | awk -F'\t' -v p="$prefix" 'index($2, p)==1 { print $1 }'
}

# --- ingest ------------------------------------------------------------------

add_staged() {
  local stagedir="$1" f
  local -a files=()
  while IFS= read -r f; do files+=("$f"); done < <(fd -t f . "$stagedir")
  if ((${#files[@]} == 0)); then
    die "nothing staged; refusing to run 'cognee add'"
  fi
  local batch=30 i
  for ((i = 0; i < ${#files[@]}; i += batch)); do
    run cognee add "${files[@]:i:batch}" -d "$DATASET"
  done
}

# cognify in the background (foreground calls ReadTimeout), then poll dataset
# status to completion; retry cognify up to 3x on a processing error.
cognify_and_poll() {
  local uuid="$1" attempt status poll poll_max=40
  for attempt in 1 2 3; do
    run cognee cognify -d "$DATASET" --background
    if [[ "$DRY_RUN" == true ]]; then
      log "[dry-run] would poll 'cognee datasets status $uuid' until DATASET_PROCESSING_COMPLETED"
      return 0
    fi
    for ((poll = 1; poll <= poll_max; poll++)); do
      sleep 30
      status="$(cognee datasets status "$uuid" 2>/dev/null || true)"
      log "cognify attempt $attempt poll $poll: $status"
      case "$status" in
        *DATASET_PROCESSING_COMPLETED*) return 0 ;;
        *DATASET_PROCESSING_ERRORED*) break ;;
      esac
    done
  done
  die "cognify did not reach DATASET_PROCESSING_COMPLETED after 3 attempts"
}

# --- path validation for `add` ----------------------------------------------

is_in_scope_path() {
  local p="$1"
  is_special_doc "$p" && return 0
  [[ "$p" == "$PLUGINS_ROOT/"*"/.apm/skills/"*.md ]] || return 1
  [[ "$p" == *"/apm_modules/"* ]] && return 1
  [[ "$p" == *"/.lake/"* ]] && return 1
  [[ -f "$p" ]]
}

# --- verbs -------------------------------------------------------------------

verb_refresh() {
  local uuid stagedir
  case "$SCOPE" in
    all)
      stagedir="$(mktemp -d)"
      register_cleanup "$stagedir"
      stage_scope "$stagedir"
      stage_special_doc "$stagedir"
      log "prepared $STAGED_COUNT skill docs + agents-md.nix for a full rebuild of '$DATASET'"
      confirm "Full refresh WIPES dataset '$DATASET' (cognee delete -d $DATASET -f) then re-ingests $((STAGED_COUNT + 1)) docs. Proceed?"
      run cognee delete -d "$DATASET" -f
      add_staged "$stagedir"
      uuid="$(resolve_uuid "$DATASET")"
      cognify_and_poll "$uuid"
      ;;
    plugin | skill)
      uuid="$(resolve_uuid "$DATASET")"
      local prefix
      prefix="$(scope_prefix)"
      local -a ids=()
      mapfile -t ids < <(remote_data_ids "$uuid" "$prefix")
      stagedir="$(mktemp -d)"
      register_cleanup "$stagedir"
      stage_scope "$stagedir"
      log "scope $(scope_desc): forgetting ${#ids[@]} existing item(s), re-staging $STAGED_COUNT source doc(s)"
      confirm "Refresh $(scope_desc): forget ${#ids[@]} item(s) then re-add $STAGED_COUNT doc(s) in '$DATASET'. Proceed?"
      local id
      for id in "${ids[@]:-}"; do
        [[ -n "$id" ]] || continue
        run cognee forget --dataset-id "$uuid" --data-id "$id"
      done
      add_staged "$stagedir"
      cognify_and_poll "$uuid"
      ;;
    *) die "unhandled scope '$SCOPE'" ;;
  esac
}

verb_remove() {
  case "$SCOPE" in
    plugin | skill) : ;;
    *) die "'remove' requires --skill <group>/<skill> or --plugin <group>" 2 ;;
  esac
  local uuid prefix
  uuid="$(resolve_uuid "$DATASET")"
  prefix="$(scope_prefix)"
  local -a pairs=()
  mapfile -t pairs < <(remote_rows "$uuid" | awk -F'\t' -v p="$prefix" 'index($2,p)==1 { print $1 "\t" $2 }')
  if ((${#pairs[@]} == 0)); then
    log "no items match prefix '$prefix' in dataset '$DATASET'; nothing to remove"
    return 0
  fi
  log "items to remove (Name  data_id):"
  local pair id name
  for pair in "${pairs[@]}"; do
    id="${pair%%$'\t'*}"
    name="${pair#*$'\t'}"
    log "  $name  $id"
  done
  confirm "Forget ${#pairs[@]} item(s) from '$DATASET'? (targeted; no re-add)"
  for pair in "${pairs[@]}"; do
    id="${pair%%$'\t'*}"
    run cognee forget --dataset-id "$uuid" --data-id "$id"
  done
  log "note: any graph-layer residue from removed items is swept by a later full 'refresh' (scope=all)"
}

verb_add() {
  ((${#PATHS[@]} > 0)) || die "'add' requires at least one <path>" 2
  local stagedir p abspath uuid
  stagedir="$(mktemp -d)"
  register_cleanup "$stagedir"
  for p in "${PATHS[@]}"; do
    abspath="$(realpath -e -- "$p" 2>/dev/null)" || die "path not found: $p" 2
    is_in_scope_path "$abspath" \
      || die "'$p' is not an in-scope skills .md nor the agents-md.nix special doc" 2
    stage_file "$abspath" "$stagedir"
  done
  add_staged "$stagedir"
  uuid="$(resolve_uuid "$DATASET")"
  cognify_and_poll "$uuid"
}

verb_list() {
  local uuid prefix=""
  uuid="$(resolve_uuid "$DATASET")"
  case "$SCOPE" in
    all) prefix="" ;;
    plugin | skill) prefix="$(scope_prefix)" ;;
  esac
  printf '%s\t%s\n' "Name" "data_id"
  remote_rows "$uuid" | awk -F'\t' -v p="$prefix" \
    'p=="" || index($2,p)==1 { printf "%s\t%s\n", $2, $1 }'
}

verb_status() {
  local uuid count
  uuid="$(resolve_uuid "$DATASET")"
  count="$(remote_rows "$uuid" | wc -l | tr -d ' ')"
  printf 'dataset: %s (%s)\n' "$DATASET" "$uuid"
  printf 'items: %s\n' "$count"
  printf 'processing status:\n'
  cognee datasets status "$uuid"
}

# --- argument parsing --------------------------------------------------------

while (($#)); do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -y | --yes)
      YES=true
      shift
      ;;
    --dataset)
      DATASET="${2:?--dataset requires a NAME}"
      shift 2
      ;;
    --scope)
      set_scope "${2:?--scope requires a value}"
      shift 2
      ;;
    --skill)
      set_scope_skill "${2:?--skill requires <group>/<skill>}"
      shift 2
      ;;
    --plugin)
      set_scope_plugin "${2:?--plugin requires <group>}"
      shift 2
      ;;
    --all)
      SCOPE=all
      shift
      ;;
    --)
      shift
      while (($#)); do
        PATHS+=("$1")
        shift
      done
      ;;
    -*)
      usage >&2
      die "unknown flag: $1" 2
      ;;
    *)
      if [[ -z "$VERB" ]]; then VERB="$1"; else PATHS+=("$1"); fi
      shift
      ;;
  esac
done

[[ -n "$VERB" ]] || VERB="refresh"

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || die "not inside a git repository (run from within the vanixiets checkout)"
PLUGINS_ROOT="$REPO_ROOT/modules/home/ai/plugins"

case "$VERB" in
  refresh) verb_refresh ;;
  remove) verb_remove ;;
  add) verb_add ;;
  list) verb_list ;;
  status) verb_status ;;
  *)
    usage >&2
    die "unknown verb: $VERB" 2
    ;;
esac
