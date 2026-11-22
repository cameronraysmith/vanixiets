# Stop hook of the claude-sandbox profile: publishes the session's transcript
# after each turn as `<key>.jsonl` plus `session.json` on the branch
# `claude/transcripts/<key>`, a new orphan on the first turn and a fast-forward
# after that. default.nix defines log_dir above this text.
#
# It works in a scratch bare repository under /tmp, never in the session's own
# checkout, and pushes to that checkout's push URL for origin, so the push uses
# the same credentials as the session's own pushes (the harness's
# credential.https://github.com.helper). A gitleaks finding pushes nothing. It
# prints nothing, bounds each network step, and always exits 0.

record() {
  mkdir -p "$log_dir" 2>/dev/null &&
    printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" >>"$log_dir/transcripts.log" 2>/dev/null
}

# The branch key: the cloud session id (session_01…) from the transcript's
# remote_session_change record, which is where the cloud writes it (no
# environment variable holds it: probe of 2026-11-22); else the cloud-local
# uuid from the hook input. The one place to change the id source.
session_key() {
  local transcript=$1 uuid=$2 id
  id=$(jq -rR 'fromjson? | select(.type == "attachment" and .attachment.type == "remote_session_change")
    | .attachment.url // empty | capture("/code/(?<id>session_[A-Za-z0-9]+)").id' "$transcript" 2>/dev/null | tail -n 1)
  echo "${id:-$uuid}"
}

# session.json: the ids, the first prompt's first line and the start time from
# the transcript, the checkout commit, and the setup marker's fields.
session_meta() {
  local transcript=$1 uuid=$2 key=$3 checkout=$4 marker=$5
  jq -nR --arg uuid "$uuid" --arg key "$key" --arg checkout "$checkout" --arg marker "$marker" '
    [inputs | fromjson?] as $r
    | ($marker | [splits(" ")] | map(capture("^(?<key>[a-zA-Z]+)=(?<value>.*)$")?) | from_entries) as $m
    | def field($k): ($m[$k] // null) | if . == "none" or . == "" then null else . end;
    {
      key: $key,
      uuid: $uuid,
      session: (if ($key | startswith("session_")) then $key else null end),
      first_prompt: ($r | map(select(.type == "user" and (.isMeta | not)) | .message.content
        | if type == "string" then . else (map(select(.type == "text") | .text) | first) end
        | select(. != null)) | first | if . == null then null else split("\n")[0] end),
      started: ($r | map(.timestamp // empty) | first),
      checkout: (if $checkout == "" then null else $checkout end),
      marker: {mode: field("mode"), tip: field("tip"), rev: field("rev"), dist: field("dist"), P: field("P")}
    }' "$transcript"
}

input=$(cat)
transcript=$(jq -r '.transcript_path // empty' <<<"$input" 2>/dev/null)
uuid=$(jq -r '.session_id // empty' <<<"$input" 2>/dev/null)
cwd=$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null)
if [ ! -r "$transcript" ] || [ -z "$uuid" ]; then
  record "skipped=no transcript"
  exit 0
fi
key=$(session_key "$transcript" "$uuid")
branch=refs/heads/claude/transcripts/$key

gitleaks dir "$transcript" --no-banner --redact --log-level error --exit-code 3 >/dev/null 2>&1
leaks=$?
if [ "$leaks" = 3 ]; then
  record "key=$key pushed=no reason=gitleaks"
  exit 0
elif [ "$leaks" != 0 ]; then
  record "key=$key pushed=no reason=gitleaks-error/$leaks"
  exit 0
fi

url=$(git -C "${cwd:-.}" remote get-url --push origin 2>/dev/null)
if [ -z "$url" ]; then
  record "key=$key pushed=no reason=no-origin cwd=$cwd"
  exit 0
fi
checkout=$(git -C "$cwd" rev-parse HEAD 2>/dev/null)
marker=$(tail -n 1 "$log_dir/setup.log" 2>/dev/null)

scratch=/tmp/claude-sandbox-transcripts/$key.git
# `timeout` runs programs, not shell functions, so the bounded steps call git.
g() { git --git-dir="$scratch" "$@"; }
[ -d "$scratch" ] || git init -q --bare "$scratch" >/dev/null 2>&1
if ! remote=$(timeout 20 git ls-remote "$url" "$branch" 2>/dev/null </dev/null); then
  record "key=$key pushed=no reason=ls-remote"
  exit 0
fi
parent=()
if [ -n "$remote" ]; then
  if ! timeout 30 git --git-dir="$scratch" fetch -q --depth 1 "$url" "+$branch:refs/heads/published" >/dev/null 2>&1 </dev/null; then
    record "key=$key pushed=no reason=fetch"
    exit 0
  fi
  parent=(-p "$(g rev-parse refs/heads/published)")
fi

blob=$(g hash-object -w "$transcript")
meta=$(session_meta "$transcript" "$uuid" "$key" "$checkout" "$marker" | g hash-object -w --stdin)
tree=$(printf '100644 blob %s\t%s.jsonl\n100644 blob %s\tsession.json\n' "$blob" "$key" "$meta" | g mktree)
if [ -n "$remote" ] && [ "$tree" = "$(g rev-parse 'refs/heads/published^{tree}')" ]; then
  record "key=$key pushed=no reason=unchanged"
  exit 0
fi
if ! commit=$(g commit-tree "$tree" "${parent[@]}" -m "transcript: $key" 2>/dev/null); then
  record "key=$key pushed=no reason=commit"
  exit 0
fi
if timeout 30 git --git-dir="$scratch" push -q "$url" "$commit:$branch" >/dev/null 2>&1 </dev/null; then
  record "key=$key pushed=$commit parent=${parent[1]:-none} branch=${branch#refs/heads/}"
else
  record "key=$key pushed=no reason=push commit=$commit"
fi
exit 0
