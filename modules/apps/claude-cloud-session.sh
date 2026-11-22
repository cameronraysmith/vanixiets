#!/usr/bin/env bash
# shellcheck shell=bash

usage() {
  cat <<'EOF'
Usage:
  claude-cloud-session create <name> <prompt-file> [--environment-id <env_id>]
  claude-cloud-session send <session|name> <message | ->
  claude-cloud-session wait <session|name> [--timeout <seconds>]
  claude-cloud-session fetch <session|name> [<out>]
  claude-cloud-session prune --older-than <days> [--yes]
  claude-cloud-session refresh-line

Drives Claude Code cloud sessions from the command line and reads their
transcripts from the branches the claude-sandbox profile's Stop hook pushes,
claude/transcripts/<session>.

  create  Starts a cloud session whose first message is the prompt file's
          text, named <name>-<sha7> after the commit it should start from,
          and prints its id (session_01…). Run it from a checkout of the
          repository that Claude Code trusts: the session starts from the
          newest pushed commit beneath its HEAD; when the CLI reports another,
          create warns and index.tsv records that one.
          --environment-id env_… picks the cloud environment for this session,
          passed as --settings '{"remote":{"defaultEnvironmentId":"env_…"}}'.
          Without it, ~/.claude/settings.json must set
          remote.defaultEnvironmentId, or create refuses: the CLI would take the
          newest environment. (Claude Code's own --environment takes only
          self-hosted ccpool_… ids.)
  send    Sends a follow-up message ("-" reads it from stdin); exits 1 when
          the cloud does not accept it.
  wait    Polls the session's transcript branch until its newest turn has
          finished (the last message is the assistant's, with no tool call
          pending) and holds the last prompt sent, then prints the branch.
  fetch   Writes the session's transcript to
          logs/claude-sandbox/sessions/<session>.jsonl, or <out>.
  prune   Lists transcript branches whose last commit is older than <days>;
          --yes deletes them.
  refresh-line
          Prints only the line to add, or replace, before `exit 0` in a cloud
          environment's setup script so its snapshot is rebuilt now:
          # refresh trigger <YYYY-MM-DD UTC> (main=<sha8> builds <hash>)
          for GitHub's main (git ls-remote, not the local HEAD), <hash> being
          the store hash of the claude-sandbox activation package that commit
          evaluates to, by a pure evaluation of github:…/<sha> with the
          caller's nix. Run it as: nix run .#claude-cloud-session -- refresh-line

A session can be named by its id or by the name create gave it, which
logs/claude-sandbox/sessions/index.tsv records. All git work happens in a
scratch repository under ${XDG_CACHE_HOME:-~/.cache}/claude-cloud-session,
never in the caller's checkout. It never teleports a session.

Exit status: 0 on success, 1 on a failure, 2 on a usage error.
EOF
}

die() {
  printf 'claude-cloud-session: %s\n' "$1" >&2
  exit "${2:-1}"
}

state=${XDG_CACHE_HOME:-$HOME/.cache}/claude-cloud-session
scratch=$state/scratch.git

# The caller's checkout, read only: its top level for logs/, and its origin.
context() {
  toplevel=$(git rev-parse --show-toplevel 2>/dev/null) || die "run it from a checkout of the repository" 2
  sessions=$toplevel/logs/claude-sandbox/sessions
  index=$sessions/index.tsv
  remote=$(git -C "$toplevel" remote get-url origin 2>/dev/null) || die "the checkout has no origin remote"
}
g() { git --git-dir="$scratch" "$@"; }

scratch_init() {
  mkdir -p "$state"
  [ -d "$scratch" ] || git init -q --bare "$scratch"
}

# index.tsv: name, session, start_commit, created (UTC), prompt's first line.
index_add() {
  mkdir -p "$sessions"
  [ -s "$index" ] || printf 'name\tsession\tstart_commit\tcreated\tfirst_prompt\n' >"$index"
  printf '%s\t%s\t%s\t%s\t%s\n' "$@" >>"$index"
}

# Prints the session id for an id or a name in index.tsv.
resolve() {
  if [[ $1 == session_* ]]; then
    echo "$1"
    return
  fi
  [ -r "$index" ] || die "no session named $1 (no $index)"
  awk -F '\t' -v n="$1" 'NR > 1 && ($1 == n || substr($1, 1, length(n) + 1) == n "-") { s = $2 } END { if (s) print s; else exit 1 }' "$index" ||
    die "no session named $1 in $index"
}

# Prints the session's transcript branch: claude/transcripts/<session>, or, when
# the cloud did not record its id, the uuid-keyed branch whose session.json holds
# the first prompt line create recorded.
branch_of() {
  local id=$1 prompt refs ref
  if [ -n "$(git ls-remote "$remote" "refs/heads/claude/transcripts/$id")" ]; then
    echo "claude/transcripts/$id"
    return
  fi
  prompt=$(awk -F '\t' -v s="$id" 'NR > 1 && $2 == s { p = $5 } END { print p }' "$index" 2>/dev/null)
  [ -n "$prompt" ] || return 1
  fetch_transcript_refs 2>/dev/null || return 1
  for ref in "${refs[@]}"; do
    [[ $ref == */session_* ]] && continue
    if [ "$(g show "$ref:session.json" 2>/dev/null | jq -r '.first_prompt // empty')" = "$prompt" ]; then
      echo "${ref#refs/heads/}"
      return
    fi
  done
  return 1
}

# Sets refs to the remote's transcript branches and fetches their tips into the
# scratch repository.
fetch_transcript_refs() {
  local ref specs=()
  mapfile -t refs < <(git ls-remote "$remote" 'refs/heads/claude/transcripts/*' | awk '{ print $2 }')
  for ref in "${refs[@]}"; do specs+=("+$ref:$ref"); done
  [ ${#specs[@]} -gt 0 ] || return 0
  scratch_init
  g fetch -q --depth 1 "$remote" "${specs[@]}"
}

tip_of() {
  git ls-remote "$remote" "refs/heads/$1" | awk '{ print $1 }'
}

# Fetches the branch and prints its transcript.
transcript_of() {
  scratch_init
  g fetch -q --depth 1 "$remote" "+refs/heads/$1:refs/heads/$1" || return 1
  g show "refs/heads/$1:${1#claude/transcripts/}.jsonl"
}

# Prints "<prompts> <finished>" for a transcript: how many prompts it holds
# (user messages with text, not tool results or meta records), and whether its
# turn has finished: the last user or assistant record (sidechains aside) is the
# assistant's, with no tool_use block waiting for a result.
turn_state() {
  jq -rsR '[split("\n")[] | fromjson? | select((.type == "user" or .type == "assistant") and (.isSidechain != true))]
    | ([.[] | select(.type == "user" and (.isMeta | not) and (.message.content
        | if type == "string" then true else any(.[]?; .type == "text") end))] | length) as $prompts
    | last as $last
    | ($last != null and $last.type == "assistant"
        and ($last.message.content | if type == "array" then map(.type) | index("tool_use") == null else true end)) as $done
    | "\($prompts) \($done)"'
}

cmd_create() {
  [ $# -ge 2 ] || die "create needs <name> <prompt-file>" 2
  local name=$1 file=$2 env='' n predicted full log out id printed start settings=()
  shift 2
  while [ $# -gt 0 ]; do
    case $1 in
      --environment-id) env=${2:?--environment-id needs an env_… id}; shift 2 ;;
      *) die "unknown option $1" 2 ;;
    esac
  done
  [ -r "$file" ] || die "cannot read $file" 2
  if [ -n "$env" ]; then
    settings=(--settings "{\"remote\":{\"defaultEnvironmentId\":\"$env\"}}")
  elif ! jq -e '.remote.defaultEnvironmentId | strings | length > 0' "$HOME/.claude/settings.json" >/dev/null 2>&1; then
    die "no --environment-id and no remote.defaultEnvironmentId in ~/.claude/settings.json: the CLI would start the session on the newest environment" 2
  fi
  # The newest pushed commit beneath HEAD, which the CLI says it starts from.
  if n=$(git -C "$toplevel" rev-list --first-parent --count HEAD --not --remotes 2>/dev/null) &&
    predicted=$(git -C "$toplevel" rev-parse "HEAD~$n" 2>/dev/null); then :
  else
    predicted=$(git -C "$toplevel" rev-parse origin/main) || die "cannot find the commit the session starts from"
  fi
  full=$name-${predicted:0:7}
  mkdir -p "$state"
  log=$state/create-$(date -u +%Y%m%dT%H%M%SZ)-$name.log
  # The CLI needs a terminal: script(1) gives it one (util-linux or BSD syntax).
  if script --version >/dev/null 2>&1; then
    script -qec "$(printf '%q ' claude --cloud "$(cat "$file")" -n "$full" "${settings[@]}")" "$log" </dev/null >/dev/null 2>&1
  else
    script -q "$log" claude --cloud "$(cat "$file")" -n "$full" "${settings[@]}" </dev/null >/dev/null 2>&1
  fi
  out=$(tr -d '\r' <"$log" | sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g')
  [[ $out =~ claude\.ai/code/(session_[A-Za-z0-9]+) ]] || die "no session id in the CLI's output ($log)"
  id=${BASH_REMATCH[1]}
  start=$predicted
  if [[ $out =~ starts\ from[^\(]*\(([0-9a-f]{7,40})\) ]]; then
    printed=${BASH_REMATCH[1]}
    start=$(git -C "$toplevel" rev-parse "$printed^{commit}" 2>/dev/null || echo "$printed")
    # The name keeps the prediction: /rename does not change the claude.ai title.
    [ "${start:0:7}" = "${predicted:0:7}" ] ||
      printf 'claude-cloud-session: %s starts from %s, not the predicted %s; index.tsv records %s\n' \
        "$full" "${start:0:7}" "${predicted:0:7}" "${start:0:7}" >&2
  fi
  index_add "$full" "$id" "$start" "$(date -u +%FT%TZ)" "$(head -n 1 "$file")"
  echo "$id"
}

cmd_send() {
  [ $# -eq 2 ] || die "send needs <session|name> <message|->" 2
  local id msg reply branch now=''
  id=$(resolve "$1")
  if [ "$2" = - ]; then msg=$(cat); else msg=$2; fi
  reply=$(claude -p "$msg" --cloud "$id" --output-format json </dev/null) || die "claude -p failed"
  echo "$reply"
  # wait then looks for a finished turn holding this prompt too: one more prompt
  # than published now, or two when nothing is published yet.
  if branch=$(branch_of "$id" 2>/dev/null); then
    read -r now _ < <(transcript_of "$branch" | turn_state) || true
  fi
  mkdir -p "$state"
  echo $((${now:-1} + 1)) >"$state/$id.prompts"
  jq -e '.ok == true' <<<"$reply" >/dev/null || exit 1
}

cmd_wait() {
  [ $# -ge 1 ] || die "wait needs <session|name>" 2
  local id timeout=1800 deadline branch want=1 prompts finished
  id=$(resolve "$1")
  shift
  while [ $# -gt 0 ]; do
    case $1 in
      --timeout) timeout=${2:?--timeout needs seconds}; shift 2 ;;
      *) die "unknown option $1" 2 ;;
    esac
  done
  [ -r "$state/$id.prompts" ] && want=$(cat "$state/$id.prompts")
  deadline=$(($(date +%s) + timeout))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    if branch=$(branch_of "$id") && read -r prompts finished < <(transcript_of "$branch" | turn_state) &&
      [ "$finished" = true ] && [ "$prompts" -ge "$want" ]; then
      echo "$branch"
      return 0
    fi
    sleep 20
  done
  die "no finished turn of $id within ${timeout}s"
}

cmd_fetch() {
  [ $# -ge 1 ] || die "fetch needs <session|name>" 2
  local id branch out
  id=$(resolve "$1")
  branch=$(branch_of "$id") || die "no transcript branch for $id yet"
  out=${2:-$sessions/$id.jsonl}
  mkdir -p "$(dirname "$out")"
  transcript_of "$branch" >"$out" || die "cannot read $branch"
  echo "$out"
}

cmd_prune() {
  local days='' yes=0 cutoff refs ref old=()
  while [ $# -gt 0 ]; do
    case $1 in
      --older-than) days=${2:?--older-than needs days}; shift 2 ;;
      --yes) yes=1; shift ;;
      *) die "unknown option $1" 2 ;;
    esac
  done
  [[ $days =~ ^[0-9]+$ ]] || die "prune needs --older-than <days>" 2
  cutoff=$(($(date +%s) - days * 86400))
  fetch_transcript_refs || die "cannot fetch the transcript branches"
  for ref in "${refs[@]}"; do
    if [ "$(g log -1 --format=%ct "$ref")" -lt "$cutoff" ]; then
      old+=("$ref")
      printf '%s %s\n' "$(g log -1 --format=%cs "$ref")" "${ref#refs/heads/}"
    fi
  done
  if [ "$yes" = 1 ] && [ ${#old[@]} -gt 0 ]; then
    g push -q "$remote" "${old[@]/#/:}" || die "cannot delete the branches"
    printf 'deleted %s branches\n' "${#old[@]}"
  elif [ ${#old[@]} -gt 0 ]; then
    printf 'dry run: --yes deletes these %s branches\n' "${#old[@]}"
  fi
}

# The refresh-trigger line for origin's main: its commit and the store hash of
# the claude-sandbox activation package it evaluates to.
cmd_refresh_line() {
  [ $# -eq 0 ] || die "refresh-line takes no arguments" 2
  local repo=cameronraysmith/vanixiets rev path base
  rev=$(git ls-remote "https://github.com/$repo" refs/heads/main | awk '{ print $1 }')
  [[ $rev =~ ^[0-9a-f]{40}$ ]] || die "cannot read main from https://github.com/$repo"
  printf 'claude-cloud-session: evaluating the claude-sandbox activation package at main=%s\n' "${rev:0:8}" >&2
  path=$(nix eval --raw "github:$repo/$rev#homeConfigurations.\"claude-sandbox@x86_64-linux\".activationPackage.outPath") ||
    die "cannot evaluate the claude-sandbox activation package at $rev"
  base=${path##*/}
  printf '# refresh trigger %s (main=%s builds %s)\n' "$(date -u +%F)" "${rev:0:8}" "${base:0:32}"
}

case ${1:-} in
  create | send | wait | fetch | prune)
    c=$1
    shift
    context
    "cmd_$c" "$@"
    ;;
  refresh-line)
    shift
    cmd_refresh_line "$@"
    ;;
  -h | --help) usage ;;
  *) usage >&2; exit 2 ;;
esac
