#!/usr/bin/env bash
# Clean secrets from shell history using atuin and gitleaks
set -euo pipefail

case "${1:-}" in
  -h|--help)
    cat <<'HELP'
Clean secrets from shell history using atuin and gitleaks

Usage: clean-shell-history-secrets

Scans all command history via atuin for potential secrets using gitleaks,
then removes any history entries containing detected secrets.

Steps:
  1. Export all atuin history (up to 100M entries)
  2. Scan with gitleaks for secret patterns
  3. Delete matching history entries from atuin
  4. Clean up temporary files

Example:
  clean-shell-history-secrets    # Scan and clean history
HELP
    exit 0
    ;;
esac

# Create temporary file for gitleaks report
report_file=$(mktemp -t gitleaks-report.XXXXXX)
trap 'rm -f "$report_file"' EXIT

echo "Scanning command history for secrets..."

# Export history and scan with gitleaks
# Note: gitleaks exits with 1 when secrets are found, which is expected
set +e
atuin search --limit 100000000 --filter-mode global | gitleaks detect --pipe -r "$report_file"
gitleaks_status=$?
set -e

# gitleaks exit codes: 0 = no leaks, 1 = leaks found, 2+ = error
if [ $gitleaks_status -gt 1 ]; then
  echo "Error: gitleaks failed with status $gitleaks_status" >&2
  exit 1
fi

# Check if any secrets were found
if [ ! -s "$report_file" ]; then
  echo "No secrets found in command history"
  exit 0
fi

secret_count=$(jq '. | length' "$report_file" 2>/dev/null || echo "0")
if [ "$secret_count" -eq 0 ]; then
  echo "No secrets found in command history"
  exit 0
fi

echo "Found $secret_count secret(s) in command history"
echo "Deleting entries containing secrets..."

# Extract unique secrets and delete corresponding history entries
jq -r '.[].Secret' "$report_file" | sort -u | while IFS= read -r secret; do
  # Show truncated secret for logging without exposing full value
  echo "  Deleting entries containing: ${secret:0:10}..."
  atuin search --delete "$secret" 2>/dev/null || true
done

echo "History cleanup complete"
