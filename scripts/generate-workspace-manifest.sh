#!/usr/bin/env bash
# Generate workspace manifest for migrating development environment between machines
#
# Scans ~/projects/*-workspace/ directories and captures git repository state
# including remotes, default branches, and relative paths. Outputs validated
# CUE manifest (source of truth) with optional YAML export for human reading.
#
# Usage: generate-workspace-manifest.sh [OPTIONS]

set -euo pipefail

# Script directory for resolving relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCHEMA_DIR="$REPO_ROOT/schemas/workspace-manifest"
MANIFEST_DIR="$REPO_ROOT/manifests"
SCHEMA_FILE="$SCHEMA_DIR/schema.cue"
OUTPUT_FILE="$MANIFEST_DIR/workspace-manifest.cue"
YAML_FILE="$MANIFEST_DIR/workspace-manifest.yaml"
DEBUG_JSON_FILE="$MANIFEST_DIR/workspace-manifest.json"

# Configuration
PROJECTS_DIR="${HOME}/projects"
WORKSPACE_PATTERN="*-workspace"

# Flags
DEBUG=false
DRY_RUN=false
QUIET=false
WORKSPACE_FILTER=""

# Statistics
WARN_COUNT=0
TOTAL_WORKSPACES=0
TOTAL_REPOS=0

# Colors for output
if [ -t 1 ]; then
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  NC='\033[0m'
else
  GREEN=''
  RED=''
  YELLOW=''
  BLUE=''
  NC=''
fi

show_help() {
  cat <<'HELP'
Generate workspace manifest for development environment migration

Usage: generate-workspace-manifest.sh [OPTIONS]

Scans all ~/projects/*-workspace/ directories for git repositories and
generates a structured manifest capturing:
  - Repository paths relative to workspace
  - All remote configurations (name → URL mappings)
  - Default branch names

The manifest is validated against a CUE schema and output as CUE (source of truth)
with optional YAML export for human reading.

Options:
  --help              Show this help message
  --debug             Write intermediate JSON to manifests/ for debugging
  --dry-run           Preview what would be scanned without writing files
  --quiet             Suppress progress output (only show errors/warnings)
  --workspace NAME    Scan only the specified workspace (e.g., "nix-workspace")

Output:
  manifests/workspace-manifest.cue     CUE manifest (version controlled)
  manifests/workspace-manifest.yaml    YAML export (generated, not tracked)
  manifests/workspace-manifest.json    Raw JSON data (only with --debug)

Examples:
  generate-workspace-manifest.sh
    Scan all workspaces and generate manifest

  generate-workspace-manifest.sh --workspace nix-workspace
    Generate manifest for only nix-workspace

  generate-workspace-manifest.sh --debug --dry-run
    Preview scan and show what JSON would be generated

Notes:
  - Automatically skips git worktrees (only tracks main repositories)
  - Warns about repos with no remotes or unknown branches
  - Manifest may contain sensitive URLs if remotes include tokens
  - Exit code 0 if manifest generated (even with warnings)
  - Exit code 1 only on catastrophic failure (validation error, etc.)

HELP
}

log_info() {
  if [ "$QUIET" = false ]; then
    echo -e "${BLUE}$*${NC}" >&2
  fi
}

log_success() {
  if [ "$QUIET" = false ]; then
    echo -e "${GREEN}✓${NC} $*" >&2
  fi
}

log_warn() {
  echo -e "${YELLOW}⚠${NC} $*" >&2
  WARN_COUNT=$((WARN_COUNT + 1))
}

log_error() {
  echo -e "${RED}✗${NC} $*" >&2
}

# Parse command-line arguments
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help)
        show_help
        exit 0
        ;;
      --debug)
        DEBUG=true
        shift
        ;;
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --quiet)
        QUIET=true
        shift
        ;;
      --workspace)
        if [ -z "${2:-}" ]; then
          log_error "Error: --workspace requires workspace name"
          echo "Usage: --workspace NAME" >&2
          exit 1
        fi
        WORKSPACE_FILTER="$2"
        shift 2
        ;;
      *)
        log_error "Error: Unknown option: $1"
        echo "Try '--help' for more information." >&2
        exit 1
        ;;
    esac
  done
}

# Collect system metadata
collect_metadata() {
  local version="1.0"
  local timestamp
  local hostname

  # ISO 8601 / RFC3339 timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # macOS-aware hostname detection
  if command -v scutil &>/dev/null; then
    hostname=$(scutil --get LocalHostName 2>/dev/null || hostname -s)
  else
    hostname=$(hostname -s)
  fi

  cat <<EOF
{
  "version": "$version",
  "generated_at": "$timestamp",
  "source_host": "$hostname",
  "workspaces": {
EOF
}

# Get all remotes for a repository
# Args: $1 = repo_path
# Output: JSON object with remote name → URL mappings
get_repo_remotes() {
  local repo_path="$1"
  local remotes_json="{"
  local first=true

  while IFS=$'\t' read -r name url; do
    if [ "$first" = true ]; then
      first=false
    else
      remotes_json+=","
    fi
    # Escape quotes in URL
    url_escaped="${url//\"/\\\"}"
    remotes_json+="\"$name\":\"$url_escaped\""
  done < <(git -C "$repo_path" remote -v | grep "(fetch)" | awk '{print $1 "\t" $2}' 2>/dev/null || true)

  remotes_json+="}"
  echo "$remotes_json"
}

# Get default branch for a repository
# Args: $1 = repo_path
# Output: branch name or "unknown"
get_default_branch() {
  local repo_path="$1"
  local default_branch=""

  # Strategy 1: Fast local query (requires origin/HEAD to be set)
  default_branch=$(git -C "$repo_path" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || true)

  # Strategy 2: Network query (slower but accurate)
  if [ -z "$default_branch" ]; then
    default_branch=$(git -C "$repo_path" remote show origin 2>/dev/null | grep 'HEAD branch' | awk '{print $NF}' || true)
  fi

  # Strategy 3: Current branch as fallback
  if [ -z "$default_branch" ]; then
    default_branch=$(git -C "$repo_path" branch --show-current 2>/dev/null || true)
  fi

  # Strategy 4: Use "unknown" if all fail
  if [ -z "$default_branch" ]; then
    default_branch="unknown"
  fi

  echo "$default_branch"
}

# Scan a single workspace
# Args: $1 = workspace_path
# Output: JSON fragment for workspace
scan_workspace() {
  local workspace_path="$1"
  local workspace_name
  local repo_count=0
  local repos_json="["
  local first=true

  workspace_name=$(basename "$workspace_path")

  if [ "$QUIET" = false ]; then
    echo -n "  Scanning $workspace_name..." >&2
  fi

  # Find all direct child directories with .git
  for dir in "$workspace_path"/*; do
    [ -d "$dir" ] || continue

    local git_dir="$dir/.git"
    [ -e "$git_dir" ] || continue

    # Skip worktrees (has .git file instead of directory)
    if [ -f "$git_dir" ]; then
      if [ "$DEBUG" = true ] && [ "$QUIET" = false ]; then
        log_warn "$workspace_name/$(basename "$dir"): skipping worktree"
      fi
      continue
    fi

    # Skip bare repositories
    if [[ $(git -C "$dir" rev-parse --is-bare-repository 2>/dev/null) == "true" ]]; then
      log_warn "$workspace_name/$(basename "$dir"): skipping bare repository"
      continue
    fi

    # Valid git repository - collect data
    local repo_name
    repo_name=$(basename "$dir")
    local remotes
    remotes=$(get_repo_remotes "$dir")
    local default_branch
    default_branch=$(get_default_branch "$dir")

    # Warn about missing remotes
    if [ "$remotes" = "{}" ]; then
      log_warn "$workspace_name/$repo_name: no remotes configured"
    fi

    # Warn about unknown branch
    if [ "$default_branch" = "unknown" ]; then
      log_warn "$workspace_name/$repo_name: could not determine default branch"
    fi

    # Add to repos array
    if [ "$first" = true ]; then
      first=false
    else
      repos_json+=","
    fi

    repos_json+=$(cat <<EOF
{
      "path": "$repo_name",
      "default_branch": "$default_branch",
      "remotes": $remotes
    }
EOF
)

    repo_count=$((repo_count + 1))
    TOTAL_REPOS=$((TOTAL_REPOS + 1))
  done

  repos_json+="]"

  if [ "$QUIET" = false ]; then
    echo -e " ${GREEN}✓${NC} ($repo_count repos)" >&2
  fi

  # Return workspace JSON fragment
  cat <<EOF
"$workspace_name": {
    "path": "$workspace_name",
    "repos": $repos_json
  }
EOF
}

# Collect all workspaces
collect_all_workspaces() {
  local workspaces_json=""
  local first=true

  if [ -n "$WORKSPACE_FILTER" ]; then
    # Single workspace mode
    local workspace_path="$PROJECTS_DIR/${WORKSPACE_FILTER}"
    if [ ! -d "$workspace_path" ]; then
      log_error "Error: Workspace not found: $workspace_path"
      exit 1
    fi

    workspaces_json=$(scan_workspace "$workspace_path")
    TOTAL_WORKSPACES=1
  else
    # Scan all workspaces
    for workspace_path in "$PROJECTS_DIR"/$WORKSPACE_PATTERN/; do
      [ -d "$workspace_path" ] || continue

      if [ "$first" = true ]; then
        first=false
      else
        workspaces_json+=","
      fi

      workspaces_json+=$(scan_workspace "$workspace_path")
      TOTAL_WORKSPACES=$((TOTAL_WORKSPACES + 1))
    done
  fi

  echo "$workspaces_json"
}

# Generate complete JSON manifest
generate_json() {
  log_info "=== Workspace Manifest Generation ==="
  echo "" >&2

  if [ "$DRY_RUN" = true ]; then
    log_info "DRY RUN MODE - No files will be modified"
    echo "" >&2
  fi

  log_info "Scanning workspaces in $PROJECTS_DIR..."

  # Collect metadata header
  local json_output
  json_output=$(collect_metadata)

  # Collect all workspaces
  local workspaces
  workspaces=$(collect_all_workspaces)

  # Close JSON structure
  json_output+="$workspaces"
  json_output+=$'\n  }\n}'

  echo "$json_output"
}

# Validate JSON against CUE schema
validate_with_cue() {
  local json_data="$1"

  log_info ""
  log_info "Validating with CUE schema..."

  if [ "$DRY_RUN" = true ]; then
    log_success "Would validate against $SCHEMA_FILE"
    return 0
  fi

  if ! echo "$json_data" | cue vet "$SCHEMA_FILE" - -d '#Manifest' 2>&1; then
    log_error "CUE validation failed"
    return 1
  fi

  log_success "Schema validation passed"
  return 0
}

# Export to CUE and YAML
export_manifest() {
  local json_data="$1"

  log_info ""
  log_info "Exporting to CUE..."

  if [ "$DRY_RUN" = true ]; then
    log_success "Would write to $OUTPUT_FILE"
    log_success "Would write to $YAML_FILE"
    return 0
  fi

  # Ensure manifests directory exists
  mkdir -p "$MANIFEST_DIR"

  # Write debug JSON if requested
  if [ "$DEBUG" = true ]; then
    echo "$json_data" > "$DEBUG_JSON_FILE"
    log_success "Debug JSON written to $DEBUG_JSON_FILE"
  fi

  # Import JSON to CUE (source of truth)
  # Write JSON to temp file for import (use .json extension for CUE recognition)
  local temp_json="$MANIFEST_DIR/.workspace-manifest-temp.json"
  echo "$json_data" > "$temp_json"

  if ! cue import "$temp_json" -p manifest -l 'manifest:' -f -o "$OUTPUT_FILE"; then
    log_error "CUE import failed"
    rm -f "$temp_json"
    return 1
  fi
  rm -f "$temp_json"
  log_success "CUE manifest written to $OUTPUT_FILE"

  # Export CUE to YAML for human reading
  if ! cue export "$OUTPUT_FILE" --out yaml > "$YAML_FILE"; then
    log_error "YAML export failed"
    return 1
  fi
  log_success "YAML export written to $YAML_FILE"

  return 0
}

# Main
main() {
  parse_args "$@"

  # Verify dependencies
  if ! command -v cue &>/dev/null; then
    log_error "Error: cue command not found"
    echo "Install CUE from https://cuelang.org/docs/install/" >&2
    exit 1
  fi

  if ! command -v git &>/dev/null; then
    log_error "Error: git command not found"
    exit 1
  fi

  # Verify schema exists
  if [ ! -f "$SCHEMA_FILE" ]; then
    log_error "Error: Schema file not found: $SCHEMA_FILE"
    exit 1
  fi

  # Generate JSON manifest
  json_data=$(generate_json)

  # Validate with CUE
  if ! validate_with_cue "$json_data"; then
    exit 1
  fi

  # Export to CUE and YAML
  if ! export_manifest "$json_data"; then
    exit 1
  fi

  # Summary - count from generated manifest if not dry run
  echo "" >&2
  log_info "=== Summary ==="

  if [ "$DRY_RUN" = false ] && [ -f "$YAML_FILE" ]; then
    # Count workspaces and repos from generated YAML (account for manifest: wrapper)
    local workspace_count
    local repo_count
    workspace_count=$(grep -c "^    [a-zA-Z0-9_-]*-workspace:" "$YAML_FILE" || echo "0")
    repo_count=$(grep -c "^        - path:" "$YAML_FILE" || echo "0")
    log_success "Generated manifest for $workspace_count workspace(s) with $repo_count repositories"
  else
    log_success "Generated manifest for $TOTAL_WORKSPACES workspace(s) with $TOTAL_REPOS repositories"
  fi

  if [ $WARN_COUNT -gt 0 ]; then
    log_warn "Total warnings: $WARN_COUNT"
  fi

  if [ "$DRY_RUN" = false ]; then
    echo "" >&2
    echo "Next steps:" >&2
    echo "  - Review CUE: cue export $OUTPUT_FILE --out yaml | head -50" >&2
    echo "  - Review YAML: cat $YAML_FILE | head -50" >&2
    echo "  - Commit: git add $OUTPUT_FILE && git commit -m 'chore: update workspace manifest'" >&2
  fi

  exit 0
}

main "$@"
