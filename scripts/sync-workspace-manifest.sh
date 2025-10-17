#!/usr/bin/env bash
# Workspace manifest synchronization tool
# Syncs local development environment to match workspace manifest

set -euo pipefail

# ============================================================================
# Constants and Defaults
# ============================================================================

SCRIPT_NAME="sync-workspace-manifest"

DEFAULT_MANIFEST="${HOME}/projects/nix-workspace/nix-config/manifests/workspace-manifest.cue"
DEFAULT_SCHEMA="${HOME}/projects/nix-workspace/nix-config/schemas/workspace-manifest/schema.cue"
DEFAULT_PROJECTS_ROOT="${HOME}/projects"

MANIFEST_FILE="${DEFAULT_MANIFEST}"
SCHEMA_FILE="${DEFAULT_SCHEMA}"
PROJECTS_ROOT="${DEFAULT_PROJECTS_ROOT}"

MODE="verify"  # verify | sync | dry-run
QUIET=false
VERBOSE=false
WORKSPACE_FILTER=""
LOG_FILE=""

# Cache for manifest JSON (to avoid repeated CUE exports)
MANIFEST_JSON_CACHE=""

# ============================================================================
# Statistics Tracking
# ============================================================================

TOTAL_WORKSPACES=0
TOTAL_REPOS=0
REPOS_OK=0
REPOS_WARN=0
REPOS_ERROR=0

# Error context arrays
declare -a CLONE_FAILURES=()
declare -a REMOTE_FAILURES=()
declare -a PERMISSION_ERRORS=()
declare -a URL_MISMATCHES=()
declare -a MISSING_REMOTES=()
declare -a SKIP_NO_REMOTES=()
declare -a SKIP_UNCOMMITTED=()

# ============================================================================
# Color Codes
# ============================================================================

if [[ -t 2 ]] && [[ "${NO_COLOR:-}" != "1" ]]; then
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  BOLD='\033[1m'
  NC='\033[0m'
else
  GREEN=''
  RED=''
  YELLOW=''
  BLUE=''
  BOLD=''
  NC=''
fi

# ============================================================================
# Logging Functions
# ============================================================================

log_to_file() {
  local level="$1"
  shift
  local message="$*"

  if [[ -n "$LOG_FILE" ]]; then
    echo "[$(date -Iseconds)] [$level] $message" >> "$LOG_FILE"
  fi
}

log_raw() {
  local message="$*"
  if [[ "$QUIET" != "true" ]]; then
    echo -e "$message" >&2
  fi
  log_to_file "INFO" "$message"
}

log_info() {
  local message="$*"
  if [[ "$QUIET" != "true" ]]; then
    echo -e "${BLUE}${message}${NC}" >&2
  fi
  log_to_file "INFO" "$message"
}

log_success() {
  local message="$*"
  if [[ "$QUIET" != "true" ]]; then
    echo -e "  ${GREEN}✓${NC} ${message}" >&2
  fi
  log_to_file "SUCCESS" "$message"
}

log_warning() {
  local message="$*"
  if [[ "$QUIET" != "true" ]]; then
    echo -e "  ${YELLOW}⚠${NC} ${message}" >&2
  fi
  log_to_file "WARNING" "$message"
}

log_error() {
  local message="$*"
  echo -e "  ${RED}✗${NC} ${message}" >&2
  log_to_file "ERROR" "$message"
}

log_verbose() {
  local message="$*"
  if [[ "$VERBOSE" == "true" ]] && [[ "$QUIET" != "true" ]]; then
    echo -e "    ${message}" >&2
  fi
  log_to_file "VERBOSE" "$message"
}

# ============================================================================
# Help Text
# ============================================================================

show_help() {
  cat <<'HELP'
Synchronize local workspace to match workspace manifest

Usage: sync-workspace-manifest [OPTIONS]

Modes:
  (default)        Verification mode - compare local state to manifest
  --sync           Sync mode - apply changes to match manifest
  --dry-run        Show what sync would do without doing it

Options:
  -h, --help              Show this help message
  -q, --quiet             Suppress progress output, show summary only
  -v, --verbose           Show detailed progress information
  -w, --workspace NAME    Process only specified workspace
  --manifest FILE         Use alternate manifest file
                          (default: ~/projects/nix-workspace/nix-config/manifests/workspace-manifest.cue)
  --projects-root DIR     Base directory for workspaces
                          (default: ~/projects)
  --log-file FILE         Write detailed log to FILE

Description:
  Reads workspace manifest and synchronizes local machine state to match.

  Verification mode (default):
    - Compares local repositories to manifest
    - Reports discrepancies without modifications
    - Safe to run on production workspaces
    - Exit 0 regardless of discrepancies found

  Sync mode (--sync):
    - Creates missing workspace directories
    - Clones missing repositories
    - Adds missing remotes to existing repositories
    - Never removes repos or modifies working trees
    - Exit 1 if any operations failed

  Dry-run mode (--dry-run):
    - Shows what sync would do without executing
    - Useful for previewing changes before sync

Safety Guarantees:
  - Never removes repositories
  - Never modifies working trees
  - Skips repos with uncommitted changes
  - Only performs additive operations
  - Continues on errors (warn and continue)

Examples:
  # Verify all workspaces match manifest
  sync-workspace-manifest

  # Verify specific workspace
  sync-workspace-manifest --workspace nix-workspace

  # Preview what sync would do
  sync-workspace-manifest --dry-run

  # Sync all workspaces
  sync-workspace-manifest --sync

  # Sync specific workspace with logging
  sync-workspace-manifest --sync --workspace planning-workspace --log-file ~/sync.log

  # Quiet mode (only show summary)
  sync-workspace-manifest --sync --quiet

Exit Codes:
  0 - Success (verify mode always returns 0)
  1 - Sync failures (operations that couldn't complete)
  2 - Catastrophic error (can't read manifest, invalid manifest, etc.)

HELP
  exit 0
}

# ============================================================================
# Argument Parsing
# ============================================================================

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        show_help
        ;;
      --sync)
        MODE="sync"
        shift
        ;;
      --dry-run)
        MODE="dry-run"
        shift
        ;;
      -q|--quiet)
        QUIET=true
        shift
        ;;
      -v|--verbose)
        VERBOSE=true
        shift
        ;;
      -w|--workspace)
        if [[ -z "${2:-}" ]]; then
          echo "Error: --workspace requires an argument" >&2
          exit 2
        fi
        WORKSPACE_FILTER="$2"
        shift 2
        ;;
      --manifest)
        if [[ -z "${2:-}" ]]; then
          echo "Error: --manifest requires an argument" >&2
          exit 2
        fi
        MANIFEST_FILE="$2"
        shift 2
        ;;
      --projects-root)
        if [[ -z "${2:-}" ]]; then
          echo "Error: --projects-root requires an argument" >&2
          exit 2
        fi
        PROJECTS_ROOT="$2"
        shift 2
        ;;
      --log-file)
        if [[ -z "${2:-}" ]]; then
          echo "Error: --log-file requires an argument" >&2
          exit 2
        fi
        LOG_FILE="$2"
        shift 2
        ;;
      *)
        echo "Error: Unknown option: $1" >&2
        echo "Try '${SCRIPT_NAME} --help' for more information." >&2
        exit 2
        ;;
    esac
  done
}

# ============================================================================
# Validation Functions
# ============================================================================

validate_dependencies() {
  local missing_deps=()

  for cmd in git cue jq; do
    if ! command -v "$cmd" &>/dev/null; then
      missing_deps+=("$cmd")
    fi
  done

  if [[ ${#missing_deps[@]} -gt 0 ]]; then
    log_error "Missing required dependencies: ${missing_deps[*]}"
    log_error "Please install missing tools and try again"
    exit 2
  fi
}

validate_manifest() {
  # Check manifest file exists
  if [[ ! -f "$MANIFEST_FILE" ]]; then
    log_error "Manifest file not found: $MANIFEST_FILE"
    exit 2
  fi

  # Check manifest is readable
  if [[ ! -r "$MANIFEST_FILE" ]]; then
    log_error "Cannot read manifest file: $MANIFEST_FILE"
    exit 2
  fi

  # Validate CUE syntax by attempting to export to JSON
  if ! cue export --out json "$MANIFEST_FILE" >/dev/null 2>&1; then
    log_error "Invalid CUE syntax in manifest: $MANIFEST_FILE"
    exit 2
  fi

  # Validate against CUE schema if schema file exists
  if [[ -f "$SCHEMA_FILE" ]]; then
    log_verbose "Validating manifest against CUE schema..."
    if ! cue vet "$MANIFEST_FILE" "$SCHEMA_FILE" 2>&1; then
      log_error "Manifest validation failed against schema"
      exit 2
    fi
    log_verbose "Manifest validation successful"
  else
    log_verbose "Schema file not found, skipping CUE validation: $SCHEMA_FILE"
  fi
}

validate_projects_root() {
  if [[ ! -d "$PROJECTS_ROOT" ]]; then
    log_error "Projects root directory does not exist: $PROJECTS_ROOT"
    exit 2
  fi

  if [[ ! -w "$PROJECTS_ROOT" ]]; then
    log_error "Projects root directory is not writable: $PROJECTS_ROOT"
    exit 2
  fi
}

# ============================================================================
# Manifest Parsing Functions (CUE source → JSON via export → jq queries)
# ============================================================================

# Helper to get manifest JSON (cached for performance)
get_manifest_json() {
  if [[ -z "$MANIFEST_JSON_CACHE" ]]; then
    # Export CUE to JSON and extract the 'manifest' field
    MANIFEST_JSON_CACHE=$(cue export --out json "$MANIFEST_FILE" 2>/dev/null | jq '.manifest')
  fi
  echo "$MANIFEST_JSON_CACHE"
}

get_workspaces() {
  get_manifest_json | jq -r '.workspaces | keys[]'
}

get_workspace_path() {
  local workspace="$1"
  get_manifest_json | jq -r ".workspaces[\"$workspace\"].path"
}

get_repo_count() {
  local workspace="$1"
  get_manifest_json | jq -r ".workspaces[\"$workspace\"].repos | length"
}

get_repo_paths() {
  local workspace="$1"
  get_manifest_json | jq -r ".workspaces[\"$workspace\"].repos[].path"
}

get_repo_remotes() {
  local workspace="$1"
  local repo_path="$2"

  # Get remotes as "name:url" pairs
  get_manifest_json | jq -r ".workspaces[\"$workspace\"].repos[] | select(.path == \"$repo_path\") | .remotes | to_entries[] | \"\(.key):\(.value)\"" 2>/dev/null || echo ""
}

# ============================================================================
# Repository Check Functions
# ============================================================================

check_repo_exists() {
  local repo_full_path="$1"
  [[ -d "$repo_full_path" ]]
}

check_is_git_repo() {
  local repo_full_path="$1"
  [[ -d "$repo_full_path/.git" ]]
}

check_uncommitted_changes() {
  local repo_full_path="$1"

  # Check for uncommitted changes (modified, added, deleted)
  if ! git -C "$repo_full_path" diff-index --quiet HEAD -- 2>/dev/null; then
    return 1  # Has uncommitted changes
  fi

  # Check for untracked files that are staged
  if ! git -C "$repo_full_path" diff --cached --quiet 2>/dev/null; then
    return 1  # Has staged changes
  fi

  return 0  # Clean working tree
}

get_actual_remotes() {
  local repo_full_path="$1"

  # Get remotes as "name url" pairs
  git -C "$repo_full_path" remote -v 2>/dev/null | grep "(fetch)" | awk '{print $1 ":" $2}'
}

# ============================================================================
# Verification Functions
# ============================================================================

verify_repo() {
  local workspace="$1"
  local repo_path="$2"
  local workspace_full_path="$3"
  local repo_full_path="$4"

  # Get manifest remotes
  local manifest_remotes_raw
  manifest_remotes_raw=$(get_repo_remotes "$workspace" "$repo_path")

  # Check if repo has any remotes in manifest
  if [[ -z "$manifest_remotes_raw" ]] || [[ "$manifest_remotes_raw" == "null" ]]; then
    SKIP_NO_REMOTES+=("$workspace/$repo_path")
    log_warning "$repo_path: no remotes configured in manifest (cannot clone)"
    REPOS_WARN=$((REPOS_WARN + 1))
    return 0
  fi

  # Parse manifest remotes into associative array
  declare -A manifest_remotes
  while IFS=: read -r name url; do
    if [[ -n "$name" ]] && [[ -n "$url" ]]; then
      manifest_remotes["$name"]="$url"
    fi
  done <<< "$manifest_remotes_raw"

  # Check if repo exists locally
  if ! check_repo_exists "$repo_full_path"; then
    log_warning "$repo_path: not found locally"
    if [[ "$MODE" == "sync" ]]; then
      message="(will clone)"
    elif [[ "$MODE" == "dry-run" ]]; then
      message="(would clone)"
    else
      message="(would clone with --sync)"
    fi
    log_verbose "  $message"
    REPOS_WARN=$((REPOS_WARN + 1))
    return 1  # Signal that sync is needed
  fi

  # Repo exists - verify it's a git repo
  if ! check_is_git_repo "$repo_full_path"; then
    log_error "$repo_path: exists but is not a git repository"
    REPOS_ERROR=$((REPOS_ERROR + 1))
    return 2
  fi

  # Check for uncommitted changes
  if ! check_uncommitted_changes "$repo_full_path"; then
    SKIP_UNCOMMITTED+=("$workspace/$repo_path")
    log_warning "$repo_path: has uncommitted changes (skipping git operations)"
    REPOS_WARN=$((REPOS_WARN + 1))
    return 0
  fi

  # Compare remotes
  local has_issues=false

  # Get actual remotes
  declare -A actual_remotes
  local actual_remotes_raw
  actual_remotes_raw=$(get_actual_remotes "$repo_full_path")

  while IFS=: read -r name url; do
    if [[ -n "$name" ]] && [[ -n "$url" ]]; then
      actual_remotes["$name"]="$url"
    fi
  done <<< "$actual_remotes_raw"

  # Check each manifest remote
  for remote_name in "${!manifest_remotes[@]}"; do
    local manifest_url="${manifest_remotes[$remote_name]}"
    local actual_url="${actual_remotes[$remote_name]:-}"

    if [[ -z "$actual_url" ]]; then
      # Remote missing
      MISSING_REMOTES+=("$workspace/$repo_path:$remote_name")
      log_warning "$repo_path: missing remote '$remote_name'"
      if [[ "$MODE" == "sync" ]]; then
        log_verbose "  Will add: $manifest_url"
      elif [[ "$MODE" == "dry-run" ]]; then
        log_verbose "  Would add: $manifest_url"
      else
        log_verbose "  Manifest URL: $manifest_url"
      fi
      has_issues=true
      REPOS_WARN=$((REPOS_WARN + 1))
    elif [[ "$actual_url" != "$manifest_url" ]]; then
      # URL mismatch
      URL_MISMATCHES+=("$workspace/$repo_path:$remote_name")
      log_warning "$repo_path: remote '$remote_name' URL mismatch"
      log_verbose "  Actual:   $actual_url"
      log_verbose "  Manifest: $manifest_url"
      log_verbose "  (manual resolution required)"
      has_issues=true
      REPOS_WARN=$((REPOS_WARN + 1))
    fi
  done

  if ! $has_issues; then
    log_success "$repo_path: exists with correct remotes"
    REPOS_OK=$((REPOS_OK + 1))
    return 0
  else
    return 1
  fi
}

# ============================================================================
# Sync Functions
# ============================================================================

clone_repo() {
  local workspace="$1"
  local repo_path="$2"
  local workspace_full_path="$3"
  local repo_full_path="$4"

  # Get manifest remotes
  local manifest_remotes_raw
  manifest_remotes_raw=$(get_repo_remotes "$workspace" "$repo_path")

  # Parse into associative array
  declare -A remotes
  while IFS=: read -r name url; do
    if [[ -n "$name" ]] && [[ -n "$url" ]]; then
      remotes["$name"]="$url"
    fi
  done <<< "$manifest_remotes_raw"

  if [[ ${#remotes[@]} -eq 0 ]]; then
    # Should have been caught in verify, but double-check
    return 0
  fi

  # Determine which remote to clone from (priority: origin > upstream > first alphabetically)
  local clone_remote=""
  local clone_url=""

  if [[ -n "${remotes[origin]:-}" ]]; then
    clone_remote="origin"
    clone_url="${remotes[origin]}"
  elif [[ -n "${remotes[upstream]:-}" ]]; then
    clone_remote="upstream"
    clone_url="${remotes[upstream]}"
  else
    # First alphabetically
    clone_remote=$(printf '%s\n' "${!remotes[@]}" | sort | head -1)
    clone_url="${remotes[$clone_remote]}"
  fi

  log_info "Cloning $repo_path from $clone_remote..."
  log_verbose "  URL: $clone_url"

  if [[ "$MODE" == "dry-run" ]]; then
    log_info "  [DRY-RUN] Would clone from $clone_remote"
    REPOS_OK=$((REPOS_OK + 1))
    return 0
  fi

  # Perform clone
  if git clone --quiet "$clone_url" "$repo_full_path" 2>&1 | grep -v "^Cloning"; then
    log_success "Cloned $repo_path"

    # Add remaining remotes
    for remote_name in "${!remotes[@]}"; do
      if [[ "$remote_name" != "$clone_remote" ]]; then
        local remote_url="${remotes[$remote_name]}"
        log_verbose "  Adding remote '$remote_name': $remote_url"
        if git -C "$repo_full_path" remote add "$remote_name" "$remote_url" 2>&1; then
          log_verbose "    Added remote '$remote_name'"
        else
          log_warning "    Failed to add remote '$remote_name'"
          REMOTE_FAILURES+=("$workspace/$repo_path:$remote_name")
        fi
      fi
    done

    REPOS_OK=$((REPOS_OK + 1))
    return 0
  else
    log_error "Failed to clone $repo_path from $clone_remote"
    CLONE_FAILURES+=("$workspace/$repo_path: $clone_url")
    REPOS_ERROR=$((REPOS_ERROR + 1))
    return 1
  fi
}

add_missing_remotes() {
  local workspace="$1"
  local repo_path="$2"
  local workspace_full_path="$3"
  local repo_full_path="$4"

  # Get manifest remotes
  local manifest_remotes_raw
  manifest_remotes_raw=$(get_repo_remotes "$workspace" "$repo_path")

  # Parse into associative array
  declare -A manifest_remotes
  while IFS=: read -r name url; do
    if [[ -n "$name" ]] && [[ -n "$url" ]]; then
      manifest_remotes["$name"]="$url"
    fi
  done <<< "$manifest_remotes_raw"

  # Get actual remotes
  declare -A actual_remotes
  local actual_remotes_raw
  actual_remotes_raw=$(get_actual_remotes "$repo_full_path")

  while IFS=: read -r name url; do
    if [[ -n "$name" ]] && [[ -n "$url" ]]; then
      actual_remotes["$name"]="$url"
    fi
  done <<< "$actual_remotes_raw"

  # Add missing remotes
  local added_any=false
  for remote_name in "${!manifest_remotes[@]}"; do
    local manifest_url="${manifest_remotes[$remote_name]}"
    local actual_url="${actual_remotes[$remote_name]:-}"

    if [[ -z "$actual_url" ]]; then
      # Remote is missing, add it
      if [[ "$MODE" == "dry-run" ]]; then
        log_info "  [DRY-RUN] Would add remote '$remote_name': $manifest_url"
      else
        log_info "Adding remote '$remote_name' to $repo_path"
        log_verbose "  URL: $manifest_url"

        if git -C "$repo_full_path" remote add "$remote_name" "$manifest_url" 2>&1; then
          log_success "Added remote '$remote_name' to $repo_path"
          added_any=true
        else
          log_error "Failed to add remote '$remote_name' to $repo_path"
          REMOTE_FAILURES+=("$workspace/$repo_path:$remote_name")
        fi
      fi
    fi
  done

  if $added_any || [[ "$MODE" == "dry-run" ]]; then
    REPOS_OK=$((REPOS_OK + 1))
  fi
}

sync_repo() {
  local workspace="$1"
  local repo_path="$2"
  local workspace_full_path="$3"
  local repo_full_path="$4"

  # Check if repo exists
  if ! check_repo_exists "$repo_full_path"; then
    # Need to clone
    clone_repo "$workspace" "$repo_path" "$workspace_full_path" "$repo_full_path"
    return $?
  fi

  # Repo exists - check if it's a git repo
  if ! check_is_git_repo "$repo_full_path"; then
    log_error "$repo_path: exists but is not a git repository"
    REPOS_ERROR=$((REPOS_ERROR + 1))
    return 1
  fi

  # Check for uncommitted changes
  if ! check_uncommitted_changes "$repo_full_path"; then
    SKIP_UNCOMMITTED+=("$workspace/$repo_path")
    log_warning "$repo_path: has uncommitted changes (skipping git operations)"
    REPOS_WARN=$((REPOS_WARN + 1))
    return 0
  fi

  # Add missing remotes
  add_missing_remotes "$workspace" "$repo_path" "$workspace_full_path" "$repo_full_path"
}

# ============================================================================
# Workspace Processing
# ============================================================================

process_workspace() {
  local workspace="$1"

  log_raw ""
  log_info "${BOLD}=== $workspace ===${NC}"

  # Get workspace path from manifest
  local workspace_path
  workspace_path=$(get_workspace_path "$workspace")
  local workspace_full_path="${PROJECTS_ROOT}/${workspace_path}"

  # Get repo count
  local repo_count
  repo_count=$(get_repo_count "$workspace")
  log_verbose "Processing $repo_count repositories"

  # Check if workspace directory exists
  if [[ ! -d "$workspace_full_path" ]]; then
    if [[ "$MODE" == "sync" ]]; then
      log_info "Creating workspace directory: $workspace_full_path"
      if mkdir -p "$workspace_full_path" 2>&1; then
        log_success "Created workspace directory"
      else
        log_error "Failed to create workspace directory: $workspace_full_path"
        PERMISSION_ERRORS+=("$workspace: cannot create directory")
        return 1
      fi
    elif [[ "$MODE" == "dry-run" ]]; then
      log_info "[DRY-RUN] Would create workspace directory: $workspace_full_path"
    else
      log_warning "Workspace directory does not exist: $workspace_full_path"
      log_verbose "  (would create with --sync)"
    fi
  fi

  # Check workspace directory is writable (if it exists)
  if [[ -d "$workspace_full_path" ]] && [[ ! -w "$workspace_full_path" ]]; then
    log_error "Workspace directory is not writable: $workspace_full_path"
    PERMISSION_ERRORS+=("$workspace: directory not writable")
    return 1
  fi

  # Process each repo
  local repo_paths
  repo_paths=$(get_repo_paths "$workspace")

  while IFS= read -r repo_path; do
    [[ -z "$repo_path" ]] && continue

    local repo_full_path="${workspace_full_path}/${repo_path}"

    # Basic sanity check for suspicious paths
    if [[ "$repo_path" == /* ]] || [[ "$repo_path" == *..* ]]; then
      log_error "$repo_path: suspicious path (absolute or contains ..)"
      REPOS_ERROR=$((REPOS_ERROR + 1))
      continue
    fi

    # Check if path conflicts with existing file
    if [[ -f "$repo_full_path" ]]; then
      log_error "$repo_path: path exists as file, expected directory"
      REPOS_ERROR=$((REPOS_ERROR + 1))
      continue
    fi

    TOTAL_REPOS=$((TOTAL_REPOS + 1))

    # Process based on mode
    if [[ "$MODE" == "verify" ]]; then
      verify_repo "$workspace" "$repo_path" "$workspace_full_path" "$repo_full_path" || true
    else
      # sync or dry-run mode
      set +e  # Temporarily disable exit on error
      verify_repo "$workspace" "$repo_path" "$workspace_full_path" "$repo_full_path"
      local verify_result=$?
      set -e  # Re-enable exit on error

      if [[ $verify_result -eq 1 ]]; then
        # Repo needs sync
        sync_repo "$workspace" "$repo_path" "$workspace_full_path" "$repo_full_path" || true
      fi
    fi
  done <<< "$repo_paths"

  TOTAL_WORKSPACES=$((TOTAL_WORKSPACES + 1))
}

# ============================================================================
# Summary Functions
# ============================================================================

print_summary() {
  log_raw ""
  log_raw "${BOLD}=== Summary ===${NC}"
  log_raw ""
  log_raw "Processed $TOTAL_WORKSPACES workspace(s), $TOTAL_REPOS repositories"
  log_raw ""

  # Status breakdown
  log_raw "Status:"
  log_raw "  ${GREEN}✓${NC} $REPOS_OK repos match manifest"

  if [[ $REPOS_WARN -gt 0 ]]; then
    log_raw "  ${YELLOW}⚠${NC} $REPOS_WARN repos have warnings"
  fi

  if [[ $REPOS_ERROR -gt 0 ]]; then
    log_raw "  ${RED}✗${NC} $REPOS_ERROR repos have errors"
  fi

  log_raw ""

  # Detailed breakdown
  if [[ ${#MISSING_REMOTES[@]} -gt 0 ]]; then
    log_raw "Missing remotes (${#MISSING_REMOTES[@]}):"
    for item in "${MISSING_REMOTES[@]}"; do
      log_raw "  - $item"
    done
    log_raw ""
  fi

  if [[ ${#URL_MISMATCHES[@]} -gt 0 ]]; then
    log_raw "URL mismatches (${#URL_MISMATCHES[@]}) - require manual resolution:"
    for item in "${URL_MISMATCHES[@]}"; do
      log_raw "  - $item"
    done
    log_raw ""
  fi

  if [[ ${#SKIP_NO_REMOTES[@]} -gt 0 ]]; then
    log_raw "Repos with no remotes (${#SKIP_NO_REMOTES[@]}) - cannot sync:"
    for item in "${SKIP_NO_REMOTES[@]}"; do
      log_raw "  - $item"
    done
    log_raw ""
  fi

  if [[ ${#SKIP_UNCOMMITTED[@]} -gt 0 ]]; then
    log_raw "Repos skipped (uncommitted changes) (${#SKIP_UNCOMMITTED[@]}):"
    for item in "${SKIP_UNCOMMITTED[@]}"; do
      log_raw "  - $item"
    done
    log_raw ""
  fi

  if [[ ${#CLONE_FAILURES[@]} -gt 0 ]]; then
    log_raw "${RED}Clone failures (${#CLONE_FAILURES[@]}):${NC}"
    for item in "${CLONE_FAILURES[@]}"; do
      log_raw "  - $item"
    done
    log_raw ""
  fi

  if [[ ${#REMOTE_FAILURES[@]} -gt 0 ]]; then
    log_raw "${RED}Remote add failures (${#REMOTE_FAILURES[@]}):${NC}"
    for item in "${REMOTE_FAILURES[@]}"; do
      log_raw "  - $item"
    done
    log_raw ""
  fi

  if [[ ${#PERMISSION_ERRORS[@]} -gt 0 ]]; then
    log_raw "${RED}Permission errors (${#PERMISSION_ERRORS[@]}):${NC}"
    for item in "${PERMISSION_ERRORS[@]}"; do
      log_raw "  - $item"
    done
    log_raw ""
  fi

  # Mode-specific guidance
  if [[ "$MODE" == "verify" ]]; then
    if [[ $REPOS_WARN -gt 0 ]] || [[ $REPOS_ERROR -gt 0 ]]; then
      log_raw "Run with ${BOLD}--sync${NC} to apply changes or ${BOLD}--dry-run${NC} to preview"
    else
      log_raw "${GREEN}All repositories are in sync with manifest${NC}"
    fi
  elif [[ "$MODE" == "dry-run" ]]; then
    log_raw "Run with ${BOLD}--sync${NC} to apply these changes"
  elif [[ "$MODE" == "sync" ]]; then
    if [[ $REPOS_ERROR -gt 0 ]]; then
      log_raw "${RED}Sync completed with errors${NC}"
    else
      log_raw "${GREEN}Sync completed successfully${NC}"
    fi
  fi
}

# ============================================================================
# Main Function
# ============================================================================

main() {
  parse_arguments "$@"

  # Show header
  if [[ "$QUIET" != "true" ]]; then
    log_raw "${BOLD}=== Workspace Manifest Sync ===${NC}"
    log_raw ""

    if [[ "$MODE" == "verify" ]]; then
      log_raw "Mode: ${BLUE}Verification${NC} (read-only)"
    elif [[ "$MODE" == "dry-run" ]]; then
      log_raw "Mode: ${YELLOW}Dry-run${NC} (preview changes)"
    elif [[ "$MODE" == "sync" ]]; then
      log_raw "Mode: ${GREEN}Sync${NC} (apply changes)"
    fi

    if [[ -n "$WORKSPACE_FILTER" ]]; then
      log_raw "Workspace filter: $WORKSPACE_FILTER"
    fi

    if [[ -n "$LOG_FILE" ]]; then
      log_raw "Logging to: $LOG_FILE"
    fi
  fi

  # Initialize log file if specified
  if [[ -n "$LOG_FILE" ]]; then
    {
      echo "=== Workspace Manifest Sync - $(date -Iseconds) ==="
      echo "Mode: $MODE"
      echo "Manifest: $MANIFEST_FILE"
      echo ""
    } > "$LOG_FILE"
  fi

  # Validate dependencies
  validate_dependencies

  # Validate manifest
  validate_manifest

  # Validate projects root
  validate_projects_root

  # Get workspaces to process
  local workspaces
  if [[ -n "$WORKSPACE_FILTER" ]]; then
    # Verify filtered workspace exists in manifest
    if ! get_manifest_json | jq -e ".workspaces | has(\"$WORKSPACE_FILTER\")" >/dev/null 2>&1; then
      log_error "Workspace '$WORKSPACE_FILTER' not found in manifest"
      exit 2
    fi
    workspaces="$WORKSPACE_FILTER"
  else
    workspaces=$(get_workspaces)
  fi

  # Process each workspace
  while IFS= read -r workspace; do
    [[ -z "$workspace" ]] && continue
    process_workspace "$workspace"
  done <<< "$workspaces"

  # Print summary
  print_summary

  # Determine exit code
  if [[ "$MODE" == "verify" ]]; then
    exit 0  # Verify mode always exits 0
  elif [[ $REPOS_ERROR -gt 0 ]] || [[ ${#CLONE_FAILURES[@]} -gt 0 ]] || [[ ${#REMOTE_FAILURES[@]} -gt 0 ]]; then
    exit 1  # Sync failures
  else
    exit 0  # Success
  fi
}

# ============================================================================
# Entry Point
# ============================================================================

main "$@"
