#!/usr/bin/env bash
# shellcheck shell=bash

usage() {
  cat <<'EOF'
Usage:
  langfuse-query [--table] traces [--user <id>] [--session <id>] [--name <name>]
                                  [--from <time>] [--to <time>] [--limit <n>]
  langfuse-query [--table] trace <trace-id> [--chars <n>]
  langfuse-query [--table] session <session-id> [--from <time>] [--to <time>] [--limit <n>]
  langfuse-query [--table] search <text> [--field input|output] [--user <id>] [--session <id>]
                                  [--from <time>] [--to <time>] [--limit <n>]
  langfuse-query api <resource> <action> [options]
  langfuse-query api help [<resource> [<action>]]
  langfuse-query api schema --json

Reads agent traces from the Langfuse Cloud project (EU) with the official
Langfuse CLI, read-only: anything but the read actions below exits 2 before a
request is made, and the key is a Viewer key, which Langfuse's server also
refuses writes. It is decrypted at run time from the clan secrets
langfuse-viewer-{public,secret}-key with your own sops age identity.
Options may appear before or after the arguments; "--" ends them.

  traces    Recent traces, newest first: each trace's root observation, with
            its observation count, tokens and cost from the metrics API.
  trace     One trace's observations as a tree: type, name, model, input and
            output cut to --chars characters (default 200, 0 for all), tokens
            and cost.
  session   The traces of one session, as traces --session.
  search    Observations whose input or output (--field picks one; default
            both) contains <text>: Langfuse's indexed literal search, case
            insensitive, whole tokens. Combine with --user, --session, --from.
  api       The Langfuse CLI itself, limited to these read actions:
              observations list, metrics get, scores list,
              score-configs list|get, comments list|get, models list|get,
              health get
            and its help and schema commands, which need no key. Langfuse
            Cloud's v4 API has no traces or sessions resource: a trace is the
            observations sharing a traceId, a session those sharing a
            sessionId. `langfuse-query api help observations list` lists the
            filters, including the --filter JSON (columns, operators).
  --from, --to  An ISO 8601 time, or <n>m, <n>h, <n>d or <n>w before now.
  --limit   Traces or matches to return (default 20, at most 1000).
  --table   Print an aligned table instead of JSON (not for api).

The API cannot: filter on an observation's own token counts or cost in these
subcommands (use api observations list --filter or api metrics get), search
with OR across fields in one request, or match substrings inside a token.

Exit status: 0 on an answer, 1 when Langfuse, the network or decryption
reports an error, 2 on a usage error or a refused action; api passes the
Langfuse CLI's own codes through (5: an HTTP error answer).
EOF
}

die_usage() {
  printf 'langfuse-query: %s\n' "$1" >&2
  usage >&2
  exit 2
}

# Read actions the api subcommand accepts, by canonical resource and action.
# checks.x86_64-linux.langfuse-query fails when any of them is not a GET in the
# packaged CLI's latest contract, and when any non-GET operation is accepted.
read_actions=(
  "observations list"
  "metrics get"
  "scores list"
  "score-configs list"
  "score-configs get"
  "comments list"
  "comments get"
  "models list"
  "models get"
  "health get"
)

# The CLI's global options (src/flags.ts), which it takes from anywhere on the
# command line. Only --json passes: the rest would redirect the request to
# another host or key, select an older contract, write a file or print the key.
refused_globals=(--public-key --secret-key --host --env --api-version --timeout --output --curl --show-secrets)

host=https://cloud.langfuse.com

# The key goes to the CLI through its environment only, never an argument or a
# file. sops finds the caller's age identity as it always does.
public_key="" secret_key=""
decrypt_key() {
  local sops_error
  sops_error=$(mktemp)
  # shellcheck disable=SC2064 # expand now: the path is fixed
  trap "rm -f '$sops_error'" EXIT
  if ! public_key=$(sops decrypt --extract '["data"]' "$LANGFUSE_QUERY_PUBLIC_KEY_FILE" 2>"$sops_error") ||
    ! secret_key=$(sops decrypt --extract '["data"]' "$LANGFUSE_QUERY_SECRET_KEY_FILE" 2>"$sops_error") ||
    [ -z "$public_key" ] || [ -z "$secret_key" ]; then
    printf 'langfuse-query: cannot decrypt the Langfuse Viewer key (clan secrets langfuse-viewer-{public,secret}-key) with your sops age identity; "clan secrets users add-secret <user> <secret>" adds a reader: %s\n' \
      "$(grep -m1 -o 'no identity matched any of the recipients\|Failed to get the data key[^.]*' "$sops_error" || echo "sops failed")" >&2
    exit 1
  fi
}

langfuse_call() {
  unset LANGFUSE_HOST LANGFUSE_API_VERSION LANGFUSE_PUBLIC_KEY LANGFUSE_SECRET_KEY
  LANGFUSE_PUBLIC_KEY=$public_key LANGFUSE_SECRET_KEY=$secret_key LANGFUSE_BASE_URL=$host \
    langfuse api "$@"
}

# Runs one read and prints its JSON body; exits 1 with Langfuse's message on an
# error answer.
read_json() {
  local body status=0
  # The CLI reports a --max-items cut on stderr; --limit already says it.
  body=$(langfuse_call "$@" 2> >(grep -v '^--all stopped at' >&2)) || status=$?
  if [ "$status" -ne 0 ] || ! jq -e 'type == "object" and has("data")' <<<"$body" >/dev/null 2>&1; then
    printf 'langfuse-query: Langfuse answered with an error (exit %s): %s\n' "$status" \
      "$(jq -rc '.message // . ' <<<"$body" 2>/dev/null || printf '%s' "$body")" >&2
    exit 1
  fi
  printf '%s' "$body"
}

to_time() {
  local value=$1 n unit
  if [[ $value =~ ^([0-9]+)([mhdw])$ ]]; then
    n=${BASH_REMATCH[1]} unit=${BASH_REMATCH[2]}
    case $unit in
      m) unit=minutes ;;
      h) unit=hours ;;
      d) unit=days ;;
      w) unit=weeks ;;
    esac
    date -u -d "-$n $unit" +%Y-%m-%dT%H:%M:%SZ
  elif [[ $value =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[^[:space:]]+$ ]]; then
    printf '%s\n' "$value"
  else
    die_usage "not a time: $value (ISO 8601, or <n>m, <n>h, <n>d, <n>w)"
  fi
}

table() {
  awk -F '\t' '
    { rows[NR] = $0; for (i = 1; i <= NF; i++) if (length($i) > width[i]) width[i] = length($i) }
    END {
      for (r = 1; r <= NR; r++) {
        n = split(rows[r], cell, "\t")
        line = ""
        for (i = 1; i <= n; i++) line = line (i < n ? sprintf("%-" width[i] "s  ", cell[i]) : cell[i])
        print line
      }
    }'
}

# The api subcommand: everything after `api` goes to the CLI unchanged once it
# is a help or schema command or a listed read action.
run_api() {
  local -a positional=()
  local token name refused
  for token in "$@"; do
    name=${token%%=*}
    for refused in "${refused_globals[@]}"; do
      [ "$name" != "$refused" ] || {
        printf 'langfuse-query: refusing %s: of the CLI'"'"'s global options only --json passes\n' "$refused" >&2
        exit 2
      }
    done
    [ "$name" = --json ] || positional+=("$token")
  done
  local resource=${positional[0]:-} action=${positional[1]:-} third=${positional[2]:-}
  local needs_key=true
  case $resource in
    "" | help | --help | -h | schema | __schema | __spec) needs_key=false ;;
    *)
      case $action in
        "" | help | --help | -h) needs_key=false ;;
        *)
          case $third in
            help | --help | -h) needs_key=false ;;
            *)
              local allowed=false entry
              for entry in "${read_actions[@]}"; do
                [ "$entry" != "$resource $action" ] || allowed=true
              done
              [ "$allowed" = true ] || {
                printf 'langfuse-query: refusing "%s %s": not a read action langfuse-query allows (%s)\n' \
                  "$resource" "$action" "$(printf '%s, ' "${read_actions[@]}" | sed 's/, $//')" >&2
                exit 2
              }
              ;;
          esac
          ;;
      esac
      ;;
  esac
  [ "$needs_key" = false ] || decrypt_key
  local status=0
  langfuse_call "$@" || status=$?
  exit "$status"
}

[ "$#" -ge 1 ] || die_usage "missing subcommand"
if [ "$1" = api ]; then
  shift
  run_api "$@"
fi

table_out=false
user="" session="" name="" from="" to="" limit=20 chars=200 field=""
positional=()
while [ "$#" -gt 0 ]; do
  case $1 in
    -h | --help)
      usage
      exit 0
      ;;
    --table) table_out=true ;;
    --user | --session | --name | --from | --to | --limit | --chars | --field)
      [ "$#" -ge 2 ] || die_usage "$1 needs a value"
      case $1 in
        --user) user=$2 ;;
        --session) session=$2 ;;
        --name) name=$2 ;;
        --from) from=$2 ;;
        --to) to=$2 ;;
        --limit) limit=$2 ;;
        --chars) chars=$2 ;;
        --field) field=$2 ;;
      esac
      shift
      ;;
    --)
      shift
      positional+=("$@")
      break
      ;;
    -?*) die_usage "unknown option: $1" ;;
    *) positional+=("$1") ;;
  esac
  shift
done

[ "${#positional[@]}" -ge 1 ] || die_usage "missing subcommand"
[[ $limit =~ ^[0-9]+$ ]] && [ "$limit" -ge 1 ] && [ "$limit" -le 1000 ] || die_usage "--limit must be 1 to 1000"
[[ $chars =~ ^[0-9]+$ ]] || die_usage "--chars must be a number"
[ -z "$from" ] || from=$(to_time "$from") || exit 2
[ -z "$to" ] || to=$(to_time "$to") || exit 2
subcommand=${positional[0]}

filters=()
[ -z "$user" ] || filters+=(--user-id "$user")
[ -z "$session" ] || filters+=(--session-id "$session")
[ -z "$from" ] || filters+=(--from-start-time "$from")
[ -z "$to" ] || filters+=(--to-start-time "$to")

case $subcommand in
  traces | session)
    if [ "$subcommand" = session ]; then
      [ "${#positional[@]}" -eq 2 ] || die_usage "session takes one session id"
      filters+=(--session-id "${positional[1]}")
    else
      [ "${#positional[@]}" -eq 1 ] || die_usage "traces takes no arguments"
    fi
    [ -z "$name" ] || filters+=(--name "$name")
    decrypt_key
    roots=$(read_json observations list --is-root-observation "${filters[@]}" \
      --fields core,basic,trace_context,metrics --limit "$limit" --all --max-items "$limit")
    ids=$(jq -c '[.data[].traceId] | unique' <<<"$roots")
    totals='{"data":[]}'
    if [ "$ids" != "[]" ]; then
      # Observations of a trace start no earlier than its root.
      query=$(jq -c --argjson ids "$ids" --arg to "$(date -u -d '+1 hour' +%Y-%m-%dT%H:%M:%SZ)" '{
        view: "observations",
        dimensions: [{field: "traceId"}],
        metrics: [{measure: "count", aggregation: "count"}, {measure: "totalTokens", aggregation: "sum"}, {measure: "totalCost", aggregation: "sum"}],
        filters: [{column: "traceId", operator: "any of", value: $ids, type: "stringOptions"}],
        orderBy: [{field: "count_count", direction: "desc"}],
        config: {row_limit: ($ids | length)},
        fromTimestamp: ([.data[].startTime] | min),
        toTimestamp: $to
      }' <<<"$roots")
      totals=$(read_json metrics get --query "$query")
    fi
    result=$(jq --argjson totals "$totals" '
      ($totals.data | map({key: .traceId, value: .}) | from_entries) as $t
      | [.data[] | {
          traceId, name: (.traceName // .name), type, startTime, latency,
          userId, sessionId, environment,
          observations: $t[.traceId].count_count,
          tokens: $t[.traceId].sum_totalTokens,
          cost: $t[.traceId].sum_totalCost
        }]
      | sort_by(.startTime) | reverse' <<<"$roots")
    if [ "$table_out" = false ]; then
      jq . <<<"$result"
      exit 0
    fi
    jq -r '["startTime", "traceId", "name", "user", "session", "obs", "tokens", "cost"],
      (.[] | [.startTime, .traceId, .name, .userId, .sessionId, .observations, .tokens, .cost]
        | map(if . == null then "-" else tostring end))
      | @tsv' <<<"$result" | table
    ;;

  trace)
    [ "${#positional[@]}" -eq 2 ] || die_usage "trace takes one trace id"
    decrypt_key
    observations=$(read_json observations list --trace-id "${positional[1]}" \
      --fields core,basic,io,model,usage --limit 1000 --all --max-items 10000)
    # Depth-first from the roots, children by start time; an observation whose
    # parent is absent counts as a root.
    result=$(jq --argjson chars "$chars" '
      def cut: if . == null then null
        else (if type == "string" then . else tojson end)
          | if $chars > 0 and length > $chars then .[0:$chars] + "…" else . end end;
      .data as $all
      | ($all | map(.id)) as $ids
      | ($all | sort_by(.startTime)) as $sorted
      | def walk_from($node; $depth):
          {depth: $depth, id: $node.id, parent: $node.parentObservationId,
           type: $node.type, name: $node.name, model: ($node.model | if . == "" then null else . end),
           startTime: $node.startTime, level: $node.level,
           input: ($node.input | cut), output: ($node.output | cut),
           tokens: (($node.usageDetails // {}) | if . == {} then null else . end),
           cost: $node.totalCost},
          ($sorted[] | select(.parentObservationId == $node.id) | walk_from(.; $depth + 1));
      [$sorted[] | select(.parentObservationId == null or (.parentObservationId as $p | $ids | index($p) | not))
        | walk_from(.; 0)]' <<<"$observations")
    if [ "$table_out" = false ]; then
      jq . <<<"$result"
      exit 0
    fi
    jq -r '["observation", "model", "tokens out/total", "cost", "input", "output"],
      (.[] | [([range(.depth) | "  "] | join("")) + .type + " " + .name, .model,
        (if .tokens == null then null else "\(.tokens.output // "-")/\(.tokens.total // "-")" end),
        .cost, .input, .output]
        | map(if . == null then "-" else tostring | gsub("[\\t\\n\\r]"; " ") end))
      | @tsv' <<<"$result" | table
    ;;

  search)
    [ "${#positional[@]}" -eq 2 ] || die_usage "search takes one text"
    text=${positional[1]}
    [ -n "$text" ] || die_usage "empty search text"
    case $field in
      "") fields=(input output) ;;
      input | output) fields=("$field") ;;
      *) die_usage "--field must be input or output" ;;
    esac
    [ -z "$name" ] || filters+=(--name "$name")
    decrypt_key
    matches='[]'
    for column in "${fields[@]}"; do
      filter=$(jq -cn --arg c "$column" --arg v "$text" '[{type: "string", column: $c, operator: "matches", value: $v}]')
      page=$(read_json observations list --filter "$filter" "${filters[@]}" \
        --fields core,basic,trace_context --limit "$limit" --all --max-items "$limit")
      matches=$(jq -c --arg c "$column" --argjson page "$page" \
        '. + [$page.data[] | {traceId, id, type, name, traceName, startTime, userId, sessionId, matched: $c}]' <<<"$matches")
    done
    result=$(jq 'group_by(.id) | map(.[0] + {matched: map(.matched) | join(",")}) | sort_by(.startTime) | reverse' <<<"$matches")
    if [ "$table_out" = false ]; then
      jq . <<<"$result"
      exit 0
    fi
    jq -r '["startTime", "traceId", "type", "name", "trace", "matched"],
      (.[] | [.startTime, .traceId, .type, .name, .traceName, .matched] | map(if . == null then "-" else tostring end))
      | @tsv' <<<"$result" | table
    ;;

  *) die_usage "unknown subcommand: $subcommand" ;;
esac
