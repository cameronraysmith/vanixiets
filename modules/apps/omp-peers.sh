#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: omp-peers [-w | --watch] [-n | --interval <seconds>] [<dir>]

Lists the interactive omp sessions whose working directory is <dir> (default:
the current directory), one per line: PID, session id, session title. These are
the PIDs agent://peers reports from inside a session in that directory, with
the session each one is on now.

The session id is the last one in the process's newest log under ~/.omp/logs,
and the title is the first line of that session's file under
~/.omp/agent/sessions. A session that has saved no messages has no file yet and
shows as untitled.

Colour follows Catppuccin Mocha when stdout is a terminal and NO_COLOR is unset.

  -w, --watch                 Keep the listing open, redrawing it in place on
                              the terminal's alternate screen; Ctrl-C exits.
  -n, --interval <seconds>    Seconds between redraws (default 2, fractions
                              allowed); implies --watch.

Exit status: 0 on a listing, 2 on a usage error.
EOF
}

readonly omp_home=$HOME/.omp

omp_main_pids() {
  ps -Ao pid=,args= | awk '$2 ~ /(^|\/)omp$/ && $3 !~ /^__omp_worker/ { print $1 }'
}

cwd_of() {
  lsof -a -d cwd -p "$1" -Fn 2>/dev/null | sed -n 's/^n//p'
}

keep_in_dir() {
  local dir=$1 pid
  while read -r pid; do
    [[ $(cwd_of "$pid") == "$dir" ]] && printf '%s\n' "$pid"
  done
  return 0
}

newest_log() {
  local -a logs=("$omp_home"/logs/omp.*."$1".log)
  [[ -e ${logs[0]} ]] && printf '%s\n' "${logs[-1]}"
  return 0
}

session_id_in() {
  [[ -n $1 ]] || return 0
  grep -o '"sessionId":"[^"]*"' "$1" | tail -n 1 | cut -d '"' -f 4
}

session_file_of() {
  [[ -n $1 ]] || return 0
  find "$omp_home/agent/sessions" -name "*_$1.jsonl" -print -quit
}

title_in() {
  [[ -n $1 ]] || return 0
  head -n 1 "$1" | jq -r 'select(.type == "title") | .title // empty'
}

describe() {
  local pid sid
  while read -r pid; do
    sid=$(session_id_in "$(newest_log "$pid")")
    printf '%s\t%s\t%s\n' "$pid" "$sid" "$(title_in "$(session_file_of "$sid")")"
  done
}

render() {
  local header pid sid none text reset
  if [[ $1 == color ]]; then
    header=$'\e[1;38;2;166;173;200m'
    pid=$'\e[38;2;250;179;135m'
    sid=$'\e[38;2;127;132;156m'
    text=$'\e[38;2;205;214;244m'
    none=$'\e[3;38;2;108;112;134m'
    reset=$'\e[0m'
  fi
  printf '%s%-7s %-36s %s%s\n' "${header-}" PID SESSION TITLE "${reset-}"
  local p s t
  while IFS=$'\t' read -r p s t; do
    if [[ -n $t ]]; then
      t=${text-}$t
    else
      t="${none-}(untitled or not yet saved)"
    fi
    printf '%s%-7s %s%-36s %s%s\n' "${pid-}" "$p" "${sid-}" "$s" "$t" "${reset-}"
  done
}

wants_color() {
  [[ -t 1 && -z ${NO_COLOR-} ]]
}

listing() {
  omp_main_pids | keep_in_dir "$1" | describe | render "$2"
}

watch_listing() {
  local dir=$1 mode=$2 interval=$3 frame footer
  trap 'printf "\e[?25h\e[?1049l"' EXIT
  trap 'exit 0' INT TERM
  printf '\e[?1049h\e[?25l'
  while :; do
    frame=$(listing "$dir" "$mode")
    footer="Every ${interval}s · $(date +%T) · Ctrl-C exits"
    [[ $mode == color ]] && footer=$'\e[38;2;108;112;134m'$footer$'\e[0m'
    printf '\e[H%s\e[K\n\e[K\n%s\e[K\e[J' "${frame//$'\n'/$'\e[K\n'}" "$footer"
    sleep "$interval"
  done
}

usage_error() {
  printf 'omp-peers: %s\n' "$1" >&2
  usage >&2
  exit 2
}

main() {
  local watch=false interval=2 dir=
  while (($#)); do
    case $1 in
      -h | --help) usage; return 0 ;;
      -w | --watch) watch=true ;;
      -n | --interval)
        (($# >= 2)) || usage_error "$1 needs a number of seconds"
        interval=$2 watch=true
        shift
        ;;
      --interval=*) interval=${1#*=} watch=true ;;
      -*) usage_error "unknown option $1" ;;
      *)
        [[ -z $dir ]] || usage_error "more than one directory given"
        dir=$1
        ;;
    esac
    shift
  done
  [[ $interval =~ ^[0-9]*\.?[0-9]+$ && $interval =~ [1-9] ]] ||
    usage_error "interval must be a positive number of seconds, not '$interval'"
  dir=$(realpath "${dir:-$PWD}")
  local mode=plain
  wants_color && mode=color
  if $watch; then
    watch_listing "$dir" "$mode" "$interval"
  else
    listing "$dir" "$mode"
  fi
}

main "$@"
