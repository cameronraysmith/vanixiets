#!/usr/bin/env bash
# Bisect nixpkgs commits to find which one broke the build
#
# Usage:
#   ./scripts/bisect-nixpkgs.sh [auto|start|step|reset|status]
#
# Commands:
#   auto   - Automatically bisect to find breaking commit (default)
#   start  - Initialize bisect (manual mode)
#   step   - Execute one bisect iteration (manual mode)
#   reset  - Clean up bisect state and restore flake.lock
#   status - Show current bisect state
#
# Environment variables:
#   NIXPKGS_REPO - Path to nixpkgs git repo (default: auto-detect)
#
# Exit codes:
#   0 - Success
#   1 - Error
#   2 - Bisect in progress (use 'step' or 'reset')

set -euo pipefail

NIX_CMD="nix --accept-flake-config"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_FILE="$REPO_ROOT/.bisect-nixpkgs-state"
FLAKE_LOCK="$REPO_ROOT/flake.lock"
FLAKE_LOCK_BACKUP="$REPO_ROOT/.flake.lock.bisect-backup"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}ℹ${NC} $*"
}

log_success() {
    echo -e "${GREEN}✓${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $*"
}

log_error() {
    echo -e "${RED}✗${NC} $*" >&2
}

# Find nixpkgs repository
find_nixpkgs_repo() {
    if [ -n "${NIXPKGS_REPO:-}" ] && [ -d "$NIXPKGS_REPO/.git" ]; then
        echo "$NIXPKGS_REPO"
        return 0
    fi

    # Try common locations
    local candidates=(
        "$HOME/projects/nix-workspace/nixpkgs"
        "$HOME/projects/nixpkgs"
        "$REPO_ROOT/../nixpkgs"
    )

    for dir in "${candidates[@]}"; do
        if [ -d "$dir/.git" ]; then
            echo "$dir"
            return 0
        fi
    done

    return 1
}

# Extract nixpkgs commit from flake.lock
get_nixpkgs_commit() {
    jq -r '.nodes.nixpkgs.locked.rev' "$FLAKE_LOCK"
}

# Get previous nixpkgs commit from git history of flake.lock
get_previous_nixpkgs_commit() {
    cd "$REPO_ROOT"

    # Get the diff of the last change to nixpkgs in flake.lock
    local old_commit
    old_commit=$(git log -2 --format="" -p -- flake.lock | \
        grep -A 1 '"nixpkgs"' | \
        grep -E '^\-.*"rev":' | \
        sed 's/.*"rev": "\([^"]*\)".*/\1/' | \
        head -1)

    if [ -z "$old_commit" ]; then
        log_error "Could not find previous nixpkgs commit in git history"
        log_info "Please provide the old commit manually:"
        log_info "  GOOD_COMMIT=<commit> $0 start"
        return 1
    fi

    echo "$old_commit"
}

# Update flake.lock to point to specific nixpkgs commit
update_flake_lock_commit() {
    local commit="$1"

    log_info "Updating flake.lock to nixpkgs commit: ${commit:0:12}..."

    # Use nix flake lock with override-input
    cd "$REPO_ROOT"
    if $NIX_CMD flake lock --override-input nixpkgs "github:nixos/nixpkgs/$commit" 2>&1 | \
        grep -v "warning:" | grep -v "trace:"; then
        log_success "Updated flake.lock"
        return 0
    else
        log_error "Failed to update flake.lock"
        return 1
    fi
}

# Save bisect state
save_state() {
    local old_commit="$1"
    local new_commit="$2"
    local nixpkgs_repo="$3"

    cat > "$STATE_FILE" <<EOF
OLD_COMMIT=$old_commit
NEW_COMMIT=$new_commit
NIXPKGS_REPO=$nixpkgs_repo
EOF
}

# Load bisect state
load_state() {
    if [ ! -f "$STATE_FILE" ]; then
        return 1
    fi

    # shellcheck source=/dev/null
    source "$STATE_FILE"

    if [ -z "${OLD_COMMIT:-}" ] || [ -z "${NEW_COMMIT:-}" ] || [ -z "${NIXPKGS_REPO:-}" ]; then
        return 1
    fi

    return 0
}

# Check if bisect is in progress
is_bisecting() {
    [ -f "$STATE_FILE" ]
}

# Start bisect
cmd_start() {
    if is_bisecting; then
        log_error "Bisect already in progress"
        log_info "Use 'status' to see current state or 'reset' to start over"
        exit 2
    fi

    log_info "=== Starting nixpkgs bisect ==="
    echo ""

    # Find nixpkgs repo
    local nixpkgs_repo
    if ! nixpkgs_repo=$(find_nixpkgs_repo); then
        log_error "Could not find nixpkgs repository"
        log_info "Please set NIXPKGS_REPO environment variable:"
        log_info "  export NIXPKGS_REPO=/path/to/nixpkgs"
        log_info "Or clone it:"
        log_info "  git clone https://github.com/nixos/nixpkgs ~/projects/nix-workspace/nixpkgs"
        exit 1
    fi
    log_success "Found nixpkgs repo: $nixpkgs_repo"

    # Get current (bad) commit
    local new_commit
    new_commit=$(get_nixpkgs_commit)
    log_info "Current (bad) commit: ${new_commit:0:12}"

    # Get previous (good) commit
    local old_commit
    if [ -n "${GOOD_COMMIT:-}" ]; then
        old_commit="$GOOD_COMMIT"
        log_info "Using provided good commit: ${old_commit:0:12}"
    else
        log_info "Detecting previous commit from git history..."
        if ! old_commit=$(get_previous_nixpkgs_commit); then
            exit 1
        fi
        log_info "Previous (good) commit: ${old_commit:0:12}"
    fi

    # Backup flake.lock
    cp "$FLAKE_LOCK" "$FLAKE_LOCK_BACKUP"
    log_success "Backed up flake.lock"

    # Calculate commit range
    cd "$nixpkgs_repo"
    local commit_count
    commit_count=$(git rev-list --count "$old_commit..$new_commit")
    local estimated_steps
    estimated_steps=$(echo "l($commit_count)/l(2)" | bc -l | xargs printf "%.0f")

    echo ""
    log_info "Commit range: $commit_count commits"
    log_info "Estimated bisect steps: ~$estimated_steps"
    echo ""

    # Start git bisect
    cd "$nixpkgs_repo"
    git bisect reset 2>/dev/null || true
    git bisect start
    git bisect bad "$new_commit"
    git bisect good "$old_commit"

    # Save state
    save_state "$old_commit" "$new_commit" "$nixpkgs_repo"

    log_success "Bisect initialized"
    echo ""
    log_info "Current bisect commit: $(git rev-parse --short HEAD)"
    log_info "Ready to test. Run: just bisect-nixpkgs step"
}

# Execute one bisect step
cmd_step() {
    if ! is_bisecting; then
        log_error "No bisect in progress"
        log_info "Start a bisect with: just bisect-nixpkgs start"
        exit 1
    fi

    if ! load_state; then
        log_error "Failed to load bisect state"
        exit 1
    fi

    cd "$NIXPKGS_REPO"

    # Check if bisect is done
    if ! git bisect log >/dev/null 2>&1; then
        log_error "No active git bisect in nixpkgs repo"
        cmd_reset
        exit 1
    fi

    local current_commit
    current_commit=$(git rev-parse HEAD)

    echo ""
    log_info "=== Testing nixpkgs commit: ${current_commit:0:12} ==="
    echo ""

    # Update flake.lock to this commit
    if ! update_flake_lock_commit "$current_commit"; then
        log_error "Failed to update flake.lock"
        exit 1
    fi

    echo ""
    log_info "Running verification..."
    echo ""

    # Run verification
    cd "$REPO_ROOT"
    if ./scripts/verify-system.sh; then
        result="good"
        log_success "Verification passed - marking as GOOD"
    else
        result="bad"
        log_error "Verification failed - marking as BAD"
    fi

    echo ""

    # Report to git bisect
    cd "$NIXPKGS_REPO"
    if git bisect "$result" | tee /tmp/bisect-output.txt | grep -q "is the first bad commit"; then
        echo ""
        log_success "=== Bisect complete! ==="
        echo ""

        local bad_commit
        bad_commit=$(git rev-parse HEAD)

        echo "First bad commit: $bad_commit"
        echo ""
        echo "GitHub link:"
        echo "  https://github.com/nixos/nixpkgs/commit/$bad_commit"
        echo ""
        echo "Commit message:"
        git log -1 --format="%B" "$bad_commit" | head -10
        echo ""

        log_info "Cleaning up..."
        cmd_reset

        log_success "Bisect finished. Review the commit above."
    else
        local current_commit_short
        current_commit_short=$(git rev-parse --short HEAD)
        log_info "Next commit to test: $current_commit_short"
        log_info "Run: just bisect-nixpkgs step"
    fi
}

# Automatic bisect (run until completion)
cmd_auto() {
    if is_bisecting; then
        log_error "Bisect already in progress"
        log_info "Use 'step' to continue or 'reset' to start over"
        exit 2
    fi

    cmd_start

    echo ""
    log_info "Running automatic bisect..."
    log_info "This may take a while. Press Ctrl-C to interrupt."
    echo ""
    sleep 2

    while is_bisecting; do
        if ! cmd_step; then
            log_error "Bisect step failed"
            exit 1
        fi

        if ! is_bisecting; then
            break
        fi

        echo ""
        log_info "Continuing to next commit..."
        sleep 1
    done
}

# Show bisect status
cmd_status() {
    if ! is_bisecting; then
        log_info "No bisect in progress"
        exit 0
    fi

    if ! load_state; then
        log_error "Failed to load bisect state"
        exit 1
    fi

    echo ""
    log_info "=== Bisect Status ==="
    echo ""
    echo "Good commit: ${OLD_COMMIT:0:12}"
    echo "Bad commit:  ${NEW_COMMIT:0:12}"
    echo "Nixpkgs repo: $NIXPKGS_REPO"
    echo ""

    cd "$NIXPKGS_REPO"
    if git bisect log >/dev/null 2>&1; then
        echo "Current commit: $(git rev-parse --short HEAD)"
        echo ""
        echo "Bisect log:"
        git bisect log | tail -10
    else
        log_warn "No active git bisect in nixpkgs repo"
    fi
}

# Reset bisect state
cmd_reset() {
    log_info "Cleaning up bisect state..."

    if load_state; then
        cd "$NIXPKGS_REPO"
        git bisect reset 2>/dev/null || true
        log_success "Reset git bisect in nixpkgs repo"
    fi

    if [ -f "$FLAKE_LOCK_BACKUP" ]; then
        mv "$FLAKE_LOCK_BACKUP" "$FLAKE_LOCK"
        log_success "Restored flake.lock from backup"
    fi

    if [ -f "$STATE_FILE" ]; then
        rm "$STATE_FILE"
        log_success "Removed state file"
    fi

    log_success "Bisect reset complete"
}

# Main command dispatcher
main() {
    local cmd="${1:-auto}"

    case "$cmd" in
        auto)
            cmd_auto
            ;;
        start)
            cmd_start
            ;;
        step)
            cmd_step
            ;;
        status)
            cmd_status
            ;;
        reset)
            cmd_reset
            ;;
        *)
            log_error "Unknown command: $cmd"
            echo ""
            echo "Usage: $0 [auto|start|step|reset|status]"
            echo ""
            echo "Commands:"
            echo "  auto   - Automatically bisect to find breaking commit (default)"
            echo "  start  - Initialize bisect (manual mode)"
            echo "  step   - Execute one bisect iteration (manual mode)"
            echo "  reset  - Clean up bisect state and restore flake.lock"
            echo "  status - Show current bisect state"
            exit 1
            ;;
    esac
}

main "$@"
