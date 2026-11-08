#!/usr/bin/env bash
# Send push notification via ntfy.zt, verifying its certificate
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

Environment:
  NTFY_TOKEN_FILE  File holding an ntfy access token; when set and non-empty,
                   the token is sent as "Authorization: Bearer" on curl's
                   stdin (-H @-), never on a command line. fleet-* topics
                   need it; host topics accept anonymous posts.
  NTFY_CACERT      The CA file ntfy.zt's certificate must chain to. The
                   package sets it to caddy's root, the public value of
                   cinnabar's clan vars caddy-root-ca.
                   ntfy-send never skips certificate verification, and
                   exits before posting when NTFY_CACERT is unset.

Examples:
  ntfy-send "build complete"
  ntfy-send "deploy finished" stibnite
  ntfy-send "alert" stibnite -H "Priority: urgent" -H "Tags: warning"
  NTFY_TOKEN_FILE=/run/secrets/vars/shared/ntfy-alerter/token ntfy-send "probe" fleet-acceptance
HELP
    exit 0
    ;;
esac

: "${NTFY_CACERT:?ntfy-send: NTFY_CACERT names no CA file}"
msg="${1:?usage: ntfy-send MESSAGE [TOPIC] [CURL_ARGS...]}"
topic="${2:-$(hostname -s)}"
shift 2 2>/dev/null || shift $#
if [ -n "${NTFY_TOKEN_FILE:-}" ]; then
  # $(< file) and printf are bash builtins, so the token is on no argv.
  token=$(< "$NTFY_TOKEN_FILE")
  printf 'Authorization: Bearer %s\n' "$token" |
    "${NTFY_CURL_BIN:-curl}" -sf --cacert "$NTFY_CACERT" -m 5 -H @- "$@" -d "$msg" "https://ntfy.zt/$topic"
else
  "${NTFY_CURL_BIN:-curl}" \
    -sf --cacert "$NTFY_CACERT" -m 5 "$@" -d "$msg" "https://ntfy.zt/$topic"
fi
