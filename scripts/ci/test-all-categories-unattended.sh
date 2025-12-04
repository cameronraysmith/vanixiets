#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Unattended CI Category Testing
# ============================================================================
# Tests all aarch64-linux matrix categories with robust error handling
# and comprehensive logging. Continues through failures to test all
# categories and provides a summary at the end.
#
# Usage:
#   ./test-all-categories-unattended.sh [system]
#
# Arguments:
#   system - Target system (default: aarch64-linux)
#
# Output:
#   - Logs to: ./ci-category-test-$(date).log
#   - Summary printed at end
# ============================================================================

SYSTEM="${1:-aarch64-linux}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="./ci-category-test-${TIMESTAMP}.log"

# Track results
declare -a SUCCEEDED
declare -a FAILED
TOTAL=0
START_TIME=$(date +%s)

# ============================================================================
# Helper Functions
# ============================================================================

log() {
    echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG_FILE"
}

test_category() {
    local system="$1"
    local category="$2"
    local config="${3:-}"

    TOTAL=$((TOTAL + 1))

    local display_name
    if [ -n "$config" ]; then
        display_name="$category/$config"
    else
        display_name="$category"
    fi

    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "Testing [$TOTAL]: $display_name ($system)"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local start=$(date +%s)

    # Run and capture both stdout and stderr
    if just ci-cache-category "$system" "$category" "$config" >> "$LOG_FILE" 2>&1; then
        local end=$(date +%s)
        local duration=$((end - start))
        log "● SUCCESS: $display_name (${duration}s)"
        SUCCEEDED+=("$display_name (${duration}s)")
    else
        local end=$(date +%s)
        local duration=$((end - start))
        log "⊘ FAILED: $display_name (${duration}s)"
        FAILED+=("$display_name (${duration}s)")
    fi

    log ""
}

# ============================================================================
# Main Execution
# ============================================================================

log "╔═══════════════════════════════════════════════════════════════╗"
log "║          Unattended CI Category Testing                      ║"
log "╚═══════════════════════════════════════════════════════════════╝"
log ""
log "System: $SYSTEM"
log "Log file: $LOG_FILE"
log "Started: $(date)"
log ""

# Verify prerequisites
log "Checking prerequisites..."

if ! sops exec-env secrets/shared.yaml 'echo $CACHIX_CACHE_NAME' &>/dev/null; then
    log "⊘ ERROR: Cannot access secrets/shared.yaml or CACHIX_CACHE_NAME not set"
    exit 1
fi

CACHE_NAME=$(sops exec-env secrets/shared.yaml 'echo $CACHIX_CACHE_NAME')
log "● Cachix cache: $CACHE_NAME"
log "   View at: https://app.cachix.org/cache/$CACHE_NAME"
log ""

# Test all categories (non-config)
log "Testing non-config categories..."
log ""

test_category "$SYSTEM" "checks-devshells"
test_category "$SYSTEM" "packages"
test_category "$SYSTEM" "home"

# Test all nixos configurations
log "Testing nixos configurations..."
log ""

test_category "$SYSTEM" "nixos" "blackphos-nixos"
test_category "$SYSTEM" "nixos" "orb-nixos"
test_category "$SYSTEM" "nixos" "stibnite-nixos"

# ============================================================================
# Summary
# ============================================================================

END_TIME=$(date +%s)
TOTAL_DURATION=$((END_TIME - START_TIME))
TOTAL_MINUTES=$((TOTAL_DURATION / 60))
TOTAL_SECONDS=$((TOTAL_DURATION % 60))

log "╔═══════════════════════════════════════════════════════════════╗"
log "║                    Test Summary                               ║"
log "╚═══════════════════════════════════════════════════════════════╝"
log ""
log "System: $SYSTEM"
log "Total categories: $TOTAL"
log "Succeeded: ${#SUCCEEDED[@]}"
log "Failed: ${#FAILED[@]}"
log "Duration: ${TOTAL_MINUTES}m ${TOTAL_SECONDS}s"
log "Completed: $(date)"
log ""

if [ ${#SUCCEEDED[@]} -gt 0 ]; then
    log "● Succeeded (${#SUCCEEDED[@]}):"
    for item in "${SUCCEEDED[@]}"; do
        log "   • $item"
    done
    log ""
fi

if [ ${#FAILED[@]} -gt 0 ]; then
    log "⊘ Failed (${#FAILED[@]}):"
    for item in "${FAILED[@]}"; do
        log "   • $item"
    done
    log ""
    log "Review failures in: $LOG_FILE"
    log "Search for '⊘ FAILED' or check logs above each failed category"
    log ""
    exit 1
else
    log "🎉 All categories tested successfully!"
    log ""
    log "Next steps:"
    log "  1. Verify cachix: https://app.cachix.org/cache/$CACHE_NAME"
    log "  2. Review log: $LOG_FILE"
    log "  3. Push changes: git push origin beta"
    log "  4. Monitor CI: gh run watch"
    log ""
    exit 0
fi
