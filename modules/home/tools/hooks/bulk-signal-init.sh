# shellcheck shell=bash
# Bulk signal table initialization for beads issues.
# Reads all open issues, identifies those without stigmergic signal tables,
# and prepends the default signal table template to their notes.

set -euo pipefail

TODAY=$(date +%Y-%m-%d)
DRY_RUN=false
CYNEFIN="complicated"
PLANNING_DEPTH=""

usage() {
  cat <<'HELP'
Bulk-initialize stigmergic signal tables on beads issues

Usage: bulk-signal-init [OPTIONS]

Scans all open beads issues and adds default stigmergic signal tables
to issues that don't already have one. Existing notes content is preserved;
the signal table is prepended.

Options:
  --dry-run         List issues that would be updated without modifying them
  --cynefin DOMAIN  Override default cynefin classification (default: complicated)
                    Valid: clear, complicated, complex, chaotic
  -h, --help        Show this help message

Examples:
  bulk-signal-init                          # Initialize all open issues
  bulk-signal-init --dry-run                # Preview what would change
  bulk-signal-init --cynefin complex        # Use complex as default domain
HELP
}

# Derive planning-depth from cynefin domain
cynefin_to_depth() {
  case "$1" in
    clear) echo "shallow" ;;
    complicated) echo "standard" ;;
    complex) echo "deep" ;;
    chaotic) echo "probe" ;;
    *)
      echo "Error: invalid cynefin domain: $1" >&2
      echo "Valid values: clear, complicated, complex, chaotic" >&2
      exit 1
      ;;
  esac
}

# Parse arguments
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --cynefin)
      if [ -z "${2:-}" ]; then
        echo "Error: --cynefin requires a value" >&2
        exit 1
      fi
      CYNEFIN="$2"
      shift 2
      ;;
    *)
      echo "Error: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

PLANNING_DEPTH=$(cynefin_to_depth "$CYNEFIN")

# Generate the signal table template
generate_signal_table() {
  cat <<EOF
<!-- stigmergic-signals -->
| Signal | Value | Updated |
|---|---|---|
| schema-version | 1 | ${TODAY} |
| cynefin | ${CYNEFIN} | ${TODAY} |
| surprise | 0.0 | ${TODAY} |
| progress | not-started | ${TODAY} |
| escalation | none | — |
| planning-depth | ${PLANNING_DEPTH} | ${TODAY} |
<!-- /stigmergic-signals -->
EOF
}

SIGNAL_TABLE=$(generate_signal_table)

# Collect all open issue IDs
ISSUE_IDS=$(bd list --status open --json --limit 0 | jq -r '.[].id')
IN_PROGRESS_IDS=$(bd list --status in_progress --json --limit 0 | jq -r '.[].id')

ALL_IDS=$(printf '%s\n%s' "$ISSUE_IDS" "$IN_PROGRESS_IDS" | sort -u)

if [ -z "$ALL_IDS" ]; then
  echo "No open or in-progress issues found."
  exit 0
fi

TOTAL=0
SKIPPED=0
INITIALIZED=0
INITIALIZED_IDS=""

while IFS= read -r issue_id; do
  if [ -z "$issue_id" ]; then
    continue
  fi

  TOTAL=$((TOTAL + 1))

  # Read current notes
  NOTES=$(bd show "$issue_id" --json | jq -r '.[0].notes // ""')

  # Check if signal table already exists
  if echo "$NOTES" | grep -q '<!-- stigmergic-signals -->'; then
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  INITIALIZED=$((INITIALIZED + 1))

  if [ -n "$INITIALIZED_IDS" ]; then
    INITIALIZED_IDS="${INITIALIZED_IDS}, ${issue_id}"
  else
    INITIALIZED_IDS="${issue_id}"
  fi

  if [ "$DRY_RUN" = true ]; then
    echo "  would initialize: ${issue_id}"
    continue
  fi

  # Prepend signal table to existing notes
  if [ -z "$NOTES" ]; then
    NEW_NOTES="$SIGNAL_TABLE"
  else
    NEW_NOTES="${SIGNAL_TABLE}
${NOTES}"
  fi

  bd update "$issue_id" --notes "$NEW_NOTES"
  echo "  initialized: ${issue_id}"

done <<< "$ALL_IDS"

# Summary
echo ""
if [ "$DRY_RUN" = true ]; then
  echo "Dry run complete."
else
  echo "Initialization complete."
fi
echo "  Total issues scanned: ${TOTAL}"
echo "  Already had signal table: ${SKIPPED}"
echo "  Initialized: ${INITIALIZED}"

if [ "$INITIALIZED" -gt 0 ]; then
  echo "  Initialized IDs: ${INITIALIZED_IDS}"
fi
