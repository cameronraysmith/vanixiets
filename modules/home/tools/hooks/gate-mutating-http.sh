# shellcheck shell=bash
# Hook: Gate mutating HTTP requests
# Auto-approves read-only curl/wget commands, and a mutating curl command only
# when every request in it goes to a trusted host.
# Returns "ask" for any other mutating request so the user is prompted.
# Does not cover httpie (http/https commands) or xh which use positional method
# arguments -- add patterns if these tools enter the workflow.
# PreToolUse:Bash (sync) -- reads JSON context from stdin.
#
# Trusted hosts (TRUSTED_HOSTS, filled in by Nix from trustedHttpMutationHosts)
# and the rule that applies them. A mutating command is allowed only when all
# of these hold, read from the command's text alone, never by running it:
# - It is one simple curl command: no unquoted ; & | ( ) < > newline, no $ or
#   backtick outside single quotes, no unquoted glob or brace characters, and
#   nothing before `curl` (no environment assignment, xargs, loop or wrapper).
# - Every option is one the hook knows. Options that change where the bytes go
#   or what is sent ask: --next/-:, -K/--config, --connect-to, --resolve,
#   -x/--proxy and the other proxy options, -L/--location, --unix-socket,
#   --doh-url, --dns-servers, --alt-svc, --variable and --expand-*. An unknown
#   option asks, since it may take the next word as its value.
# - It names at least one URL, as an operand or through --url, and each URL's
#   host is exactly a trusted host: an optional http:// or https://, no
#   userinfo (@), an optional numeric port. Case, a trailing dot, IDN or
#   percent-encoded forms do not match and ask.
# A trusted name anywhere else (a header, data, a query or a path) approves
# nothing. wget asks for every mutation, since it follows redirects by default.
# Proxies set in the session's environment or in ~/.curlrc are outside the text
# and outside this gate.

set -euo pipefail

INPUT=$(cat)

TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input // empty')
if [ -z "$TOOL_INPUT" ]; then
  exit 0
fi

COMMAND=$(echo "$TOOL_INPUT" | jq -r '.command // ""')

# Check if the command contains curl or wget as a word, wherever it stands
# (after a separator, xargs, an environment assignment or `do`).
HAS_CURL=false
HAS_WGET=false
if echo "$COMMAND" | grep -qE '(^|[^A-Za-z0-9_.-])curl([[:space:]]|$)'; then
  HAS_CURL=true
fi
if echo "$COMMAND" | grep -qE '(^|[^A-Za-z0-9_.-])wget([[:space:]]|$)'; then
  HAS_WGET=true
fi

# Not a curl/wget command; don't interfere
if ! $HAS_CURL && ! $HAS_WGET; then
  exit 0
fi

TRUSTED_HOSTS="@trustedHttpMutationHosts@"

# tokenize TEXT: splits TEXT into TOKENS by the shell's quoting rules; returns
# 1 when TEXT holds anything that makes it more than one plain command or
# whose words the text alone does not fix (an operator, an expansion, a glob).
tokenize() {
  local s=$1 i c tok="" have=0 q=""
  TOKENS=()
  for ((i = 0; i < ${#s}; i++)); do
    c=${s:i:1}
    if [ "$q" = "'" ]; then
      if [ "$c" = "'" ]; then q=""; else tok+=$c; fi
      continue
    fi
    if [ "$q" = '"' ]; then
      case $c in
        '"') q="" ;;
        '$' | '`') return 1 ;;
        \\)
          i=$((i + 1))
          tok+=${s:i:1}
          ;;
        *) tok+=$c ;;
      esac
      continue
    fi
    case $c in
      "'" | '"')
        q=$c
        have=1
        ;;
      \\)
        i=$((i + 1))
        [ "$i" -lt "${#s}" ] || return 1
        c=${s:i:1}
        [ "$c" != $'\n' ] || continue
        tok+=$c
        have=1
        ;;
      ' ' | $'\t')
        if [ "$have" = 1 ]; then
          TOKENS+=("$tok")
          tok=""
          have=0
        fi
        ;;
      ';' | '&' | '|' | '(' | ')' | '<' | '>' | '$' | '`' | '{' | '}' | '[' | ']' | '*' | '?' | '~' | '#' | '!' | $'\n')
        return 1
        ;;
      *)
        tok+=$c
        have=1
        ;;
    esac
  done
  [ -z "$q" ] || return 1
  if [ "$have" = 1 ]; then TOKENS+=("$tok"); fi
}

# curl_urls ARG...: sets URLS to the URLs curl would send to, given its
# arguments after `curl`; returns 1 when an option redirects the request, is
# unknown, or leaves the destination to something outside the text.
curl_urls() {
  local a rest letter operands=0
  URLS=()
  while [ $# -gt 0 ]; do
    a=$1
    shift
    if [ "$operands" = 1 ]; then
      URLS+=("$a")
      continue
    fi
    case $a in
      --) operands=1 ;;
      --url)
        [ $# -gt 0 ] || return 1
        URLS+=("$1")
        shift
        ;;
      --next | --config | --connect-to | --resolve | --proxy | --preproxy | --proxy-* | --socks4 | --socks4a | --socks5 | --socks5-hostname | --location | --location-trusted | --unix-socket | --abstract-unix-socket | --doh-url | --dns-servers | --alt-svc | --variable | --expand-*)
        return 1
        ;;
      --data | --data-raw | --data-binary | --data-urlencode | --data-ascii | --json | --form | --form-string | --header | --request | --output | --max-time | --connect-timeout | --user-agent | --referer | --upload-file | --cacert | --capath | --cert | --key | --user | --write-out | --retry | --retry-delay | --retry-max-time | --cookie | --cookie-jar | --oauth2-bearer | --dump-header | --stderr | --output-dir)
        [ $# -gt 0 ] || return 1
        shift
        ;;
      --silent | --show-error | --fail | --fail-with-body | --include | --verbose | --insecure | --compressed | --globoff | --get | --http1.1 | --http2 | --no-progress-meter | --ipv4 | --ipv6 | --no-buffer | --remote-name | --create-dirs)
        ;;
      --*) return 1 ;;
      -?*)
        rest=${a#-}
        while [ -n "$rest" ]; do
          letter=${rest:0:1}
          rest=${rest:1}
          case $letter in
            s | S | f | v | i | k | g | G | 4 | 6 | N | O) ;;
            d | H | X | o | m | A | e | T | u | w | F | b | c | E | D)
              if [ -z "$rest" ]; then
                [ $# -gt 0 ] || return 1
                shift
              fi
              rest=""
              ;;
            *) return 1 ;;
          esac
        done
        ;;
      *) URLS+=("$a") ;;
    esac
  done
}

# trusted_url URL: true when URL's host is exactly a trusted host.
trusted_url() {
  local u=$1 rest auth host port t
  case $u in
    http://* | https://*) rest=${u#*://} ;;
    *://*) return 1 ;;
    *) rest=$u ;;
  esac
  auth=${rest%%[/?#]*}
  case $auth in
    '' | *@*) return 1 ;;
  esac
  host=${auth%%:*}
  if [ "$host" != "$auth" ]; then
    port=${auth#*:}
    [[ $port =~ ^[0-9]+$ ]] || return 1
  fi
  for t in $TRUSTED_HOSTS; do
    [ "$host" = "$t" ] && return 0
  done
  return 1
}

# trusted_request COMMAND: true when COMMAND is one curl command whose every
# request goes to a trusted host.
trusted_request() {
  local u
  tokenize "$1" || return 1
  [ "${#TOKENS[@]}" -gt 0 ] || return 1
  [ "${TOKENS[0]}" = curl ] || return 1
  curl_urls "${TOKENS[@]:1}" || return 1
  [ "${#URLS[@]}" -gt 0 ] || return 1
  for u in "${URLS[@]}"; do
    trusted_url "$u" || return 1
  done
}

REASON=""

# --- curl mutation detection ---
if $HAS_CURL; then
  # Explicit mutating method flags
  if echo "$COMMAND" | grep -qiE -- '-X\s*(POST|PUT|DELETE|PATCH)'; then
    REASON="curl with mutating HTTP method"
  fi
  if [ -z "$REASON" ] && echo "$COMMAND" | grep -qiE -- '--request\s*(POST|PUT|DELETE|PATCH)'; then
    REASON="curl with mutating HTTP method"
  fi
  # No-space variant: -XPOST, -XPUT, etc.
  if [ -z "$REASON" ] && echo "$COMMAND" | grep -qiE -- '-X(POST|PUT|DELETE|PATCH)'; then
    REASON="curl with mutating HTTP method"
  fi
  # Implicit POST via data flags
  if [ -z "$REASON" ] && echo "$COMMAND" | grep -qE -- '(\s-d\s|--data\b|--data-raw\b|--data-binary\b|--data-urlencode\b)'; then
    REASON="curl with data payload (implicit POST)"
  fi
  # Implicit POST via form upload
  if [ -z "$REASON" ] && echo "$COMMAND" | grep -qE -- '(\s-F\s|--form\b)'; then
    REASON="curl with form upload (implicit POST)"
  fi
  # Implicit PUT via file upload
  if [ -z "$REASON" ] && echo "$COMMAND" | grep -qE -- '(\s-T\s|--upload-file\b)'; then
    REASON="curl with file upload (implicit PUT)"
  fi
  # A data, form or upload flag inside a short-option cluster (-sd, -dhi, -sF)
  # or a method flag there (-sXPOST)
  if [ -z "$REASON" ] && echo "$COMMAND" | grep -qE -- '(^|\s)-[A-Za-z0-9]*([dFT]|X\s*(POST|PUT|DELETE|PATCH))'; then
    REASON="curl with a mutating flag in an option cluster"
  fi
  # Implicit POST via --json flag
  if [ -z "$REASON" ] && echo "$COMMAND" | grep -qE -- '--json\b'; then
    REASON="curl with --json (implicit POST)"
  fi
fi

# --- wget mutation detection ---
if $HAS_WGET && [ -z "$REASON" ]; then
  if echo "$COMMAND" | grep -qE -- '(--post-data\b|--post-file\b)'; then
    REASON="wget with POST data"
  fi
  if [ -z "$REASON" ] && echo "$COMMAND" | grep -qiE -- '--method=(POST|PUT|DELETE|PATCH)'; then
    REASON="wget with mutating HTTP method"
  fi
fi

# A mutating request to trusted hosts only: approve without prompting.
if [ -n "$REASON" ] && trusted_request "$COMMAND"; then
  cat << 'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}
EOF
  exit 0
fi

# Mutating request detected: notify before escalating to user
if [ -n "$REASON" ]; then
  BRIEF=$(echo "$COMMAND" | head -c 200)
  notify-permission-wait "Bash" "$BRIEF" &>/dev/null &

  cat << EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"$REASON"}}
EOF
  exit 0
fi

# No mutating indicators detected; auto-approve as read-only
cat << 'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}
EOF
exit 0
