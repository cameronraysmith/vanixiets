#!/usr/bin/env bash
# shellcheck shell=bash

usage() {
  cat <<'EOF'
Usage:
  obs-query [--table] promql <query> [--start <time> --end <time> --step <duration>]
  obs-query [--table] sql <database> <sql>
  obs-query [--table] tql <database> <tql>

Queries the telemetry store on magnetite as its read-only regulator user.
Options may appear before or after the arguments; "--" ends them.

  promql    PromQL against the fleet database: an instant query, or a range
            query when --start, --end and --step are all given.
  sql       One SQL statement against <database>.
  tql       One TQL statement against <database>; a leading TQL keyword is
            added when absent, so "EVAL (now() - '1h'::interval, now(), '1m') up" works.
  --table   Print an aligned table instead of the store's JSON answer.

Exit status: 0 on an answer, 1 when the store or the connection reports an
error, 2 on a usage error.
EOF
}

die_usage() {
  printf 'obs-query: %s\n' "$1" >&2
  usage >&2
  exit 2
}

# Runs on magnetite under `bash -s`, read from the same stdin that then
# carries the request: bash reads a script from a pipe one byte at a time, so
# `read` and curl in main consume exactly the lines after the line that calls
# it. That line also exits, so request lines are never executed as commands.
# The request is five lines (kind, database, start, end, step) and then the
# query text up to end of input, which curl URL-encodes from stdin; the
# password goes to curl through a file descriptor, never an argument.
# Exit status 120, outside curl's and ssh's codes, means the remote side has
# already printed the one line that explains the failure.
remote_script() {
  cat <<'EOS'
set -euo pipefail
main() {
  local kind db start end step path field pw
  local pw_path=/run/secrets/vars/per-machine/magnetite/greptimedb-users/regulator-password
  IFS= read -r kind
  IFS= read -r db
  IFS= read -r start
  IFS= read -r end
  IFS= read -r step
  local -a range=()
  case $kind in
    promql) path=/v1/prometheus/api/v1/query field=query ;;
    promql-range)
      path=/v1/prometheus/api/v1/query_range field=query
      range=(--data-urlencode "start=$start" --data-urlencode "end=$end" --data-urlencode "step=$step")
      ;;
    sql) path=/v1/sql field=sql ;;
    *)
      echo "obs-query: unknown request kind" >&2
      return 2
      ;;
  esac
  if ! pw=$(sudo -n cat "$pw_path" 2>/dev/null); then
    echo "obs-query: cannot read the regulator password at $pw_path on magnetite" >&2
    return 120
  fi
  curl -sS --config <(printf 'user = "regulator:%s"\n' "$pw") \
    -H "x-greptime-db-name: $db" "${range[@]}" --data-urlencode "$field@-" \
    -w '\n%{http_code}' "http://127.0.0.1:4000$path"
}
main; exit
EOS
}

table=false
start="" end="" step=""
positional=()
while [ "$#" -gt 0 ]; do
  case $1 in
    -h | --help)
      usage
      exit 0
      ;;
    --table) table=true ;;
    --start | --end | --step)
      [ "$#" -ge 2 ] || die_usage "$1 needs a value"
      case $1 in
        --start) start=$2 ;;
        --end) end=$2 ;;
        --step) step=$2 ;;
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
subcommand=${positional[0]}
db="" query=""
case $subcommand in
  promql)
    [ "${#positional[@]}" -eq 2 ] || die_usage "promql takes one query"
    db=fleet query=${positional[1]}
    if [ -n "$start$end$step" ]; then
      [ -n "$start" ] && [ -n "$end" ] && [ -n "$step" ] ||
        die_usage "a range query needs all of --start, --end and --step"
      kind=promql-range
    else
      kind=promql
    fi
    ;;
  sql | tql)
    [ "${#positional[@]}" -eq 3 ] || die_usage "$subcommand takes a database and one statement"
    [ -z "$start$end$step" ] || die_usage "--start, --end and --step apply to promql only"
    kind=sql db=${positional[1]} query=${positional[2]}
    if [ "$subcommand" = tql ]; then
      shopt -s nocasematch
      [[ $query =~ ^[[:space:]]*tql[[:space:]] ]] || query="TQL $query"
      shopt -u nocasematch
    fi
    ;;
  *) die_usage "unknown subcommand: $subcommand" ;;
esac

[ -n "$query" ] || die_usage "empty query"
# The database becomes an HTTP header value on magnetite.
[[ $db =~ ^[A-Za-z0-9_][A-Za-z0-9_-]*$ ]] || die_usage "invalid database name: $db"
for value in "$start" "$end" "$step"; do
  [[ $value != *[[:cntrl:]]* ]] || die_usage "--start, --end and --step must be single-line values"
done

ssh_status=0
response=$(
  {
    remote_script
    printf '%s\n' "$kind" "$db" "$start" "$end" "$step"
    printf '%s' "$query"
  } | ssh -T magnetite.zt 'bash -s'
) || ssh_status=$?
if [ "$ssh_status" -eq 120 ]; then
  exit 1
elif [ "$ssh_status" -ne 0 ]; then
  printf 'obs-query: the request to magnetite failed (exit %s)\n' "$ssh_status" >&2
  exit 1
fi
if [[ $response != *$'\n'* ]]; then
  printf 'obs-query: magnetite returned no HTTP status\n' >&2
  exit 1
fi
http_status=${response##*$'\n'}
body=${response%$'\n'*}

case $kind in
  sql) answer_ok='(has("error") | not) and ((.code // 0) == 0) and (.output | type == "array") and all(.output[]; type == "object" and (has("error") | not))' ;;
  *) answer_ok='.status == "success" and (has("error") | not) and (.data.result | type == "array")' ;;
esac
if [[ ! $http_status =~ ^2[0-9][0-9]$ ]] ||
  ! jq -e "type == \"object\" and ($answer_ok)" <<<"$body" >/dev/null 2>&1; then
  message=$(jq -r '.error // empty' <<<"$body" 2>/dev/null || true)
  printf 'obs-query: the store answered HTTP %s with an error: %s\n' "$http_status" "${message:-$body}" >&2
  exit 1
fi

if [ "$table" = false ]; then
  jq . <<<"$body"
  exit 0
fi

case $kind in
  sql)
    to_tsv='.output[] | if has("records") then (.records.schema.column_schemas | map(.name)), (.records.rows[] | map(if . == null then "NULL" else tostring end)) else ["affected rows", (.affectedrows | tostring)] end | @tsv'
    ;;
  *)
    # shellcheck disable=SC2016 # jq variables, not shell expansions
    to_tsv='def labels: .metric | to_entries | map("\(.key)=\(.value)") | join(","); .data as $d | if $d.resultType == "matrix" then ["labels", "time", "value"], ($d.result[] | labels as $l | .values[] | [$l, (.[0] | tostring), .[1]]) elif $d.resultType == "vector" then ["labels", "time", "value"], ($d.result[] | [labels, (.value[0] | tostring), .value[1]]) else ["time", "value"], [($d.result[0] | tostring), ($d.result[1] | tostring)] end | @tsv'
    ;;
esac
jq -r "$to_tsv" <<<"$body" |
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
