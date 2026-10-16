#!/usr/bin/env bash
# Send push notification via ntfy.zt
set -euo pipefail

case "${1:-}" in
  -h|--help)
    cat <<'HELP'
Send push notification via ntfy.zt

Usage: ntfy-send MESSAGE [TOPIC] [CURL_ARGS...]

Arguments:
  MESSAGE     Notification body text (required)
  TOPIC       ntfy topic (default: local hostname)
  CURL_ARGS   Extra curl arguments (e.g. -H "Priority: high")

On Darwin, uses /usr/bin/curl (Apple-signed) because endpoint security
software blocks ad-hoc signed Nix store binaries from TCP connections
over ZeroTier.

Examples:
  ntfy-send "build complete"
  ntfy-send "deploy finished" stibnite
  ntfy-send "alert" stibnite -H "Priority: urgent" -H "Tags: warning"
HELP
    exit 0
    ;;
esac

msg="${1:?usage: ntfy-send MESSAGE [TOPIC] [CURL_ARGS...]}"
topic="${2:-$(hostname -s)}"
shift 2 2>/dev/null || shift $#
"${NTFY_CURL_BIN:-curl}" \
  -sfk -m 5 "$@" -d "$msg" "https://ntfy.zt/$topic"
