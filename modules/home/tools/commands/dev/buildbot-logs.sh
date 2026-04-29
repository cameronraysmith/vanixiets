#!/usr/bin/env bash
# shellcheck shell=bash
# Fetch buildbot-nix step logs (and triggered effect builds) from magnetite.
#
# Wrapped form: invoked as `buildbot-logs <builder> <build>` after activation
# via writeShellApplication in modules/home/tools/commands/_dev-tools.nix.
#
# Direct execution: `./modules/home/tools/commands/buildbot-logs.sh 48 154`
# requires `ssh` on PATH; curl/jq/sudo run inside the SSH heredoc on
# magnetite, so they are not needed locally.
#
# The wrapper injects BUILDBOT_SSH_BIN (eval-time path to ssh) via the
# nix-string preamble; standalone invocation falls back to `ssh` on PATH.
set -euo pipefail

case "${1:-}" in
  -h|--help)
    cat <<'HELP'
Fetch all step logs for a buildbot-nix build from the magnetite CI host

Usage: buildbot-logs BUILDER_ID BUILD_ID

Retrieves every non-hidden step's log (stdio plus any named logs such as
Evaluation Warnings) from the buildbot-nix master via ssh to magnetite.zt
on the ZeroTier mesh, and concatenates results to stdout with clear
step/log section headers. Intended to be redirected to a local file for
offline search, mirroring the 'gh run download -> unzip -> grep' pattern
used for GitHub Actions logs:

    buildbot-logs 48 30 > logs/buildbot-48-30.log
    rg "error:" logs/buildbot-48-30.log

Arguments:
  BUILDER_ID  Numeric builder id (e.g. 48 for the nix-eval builder of
              cameronraysmith/vanixiets)
  BUILD_ID    Build number within that builder

Environment:
  BUILDBOT_SSH_HOST         Override ssh target (default: magnetite.zt).
                            Accepts user@host form, e.g. root@magnetite.zt.
                            Leave unset to rely on local ~/.ssh/config.
  BUILDBOT_INCLUDE_HIDDEN   Set to 1 to include steps marked hidden in
                            buildbot (default: skip hidden steps).

Mapping a PR check row to BUILDER_ID/BUILD_ID:
  gh pr checks <PR> --json name,link \
    | jq -r '.[] | select(.name=="buildbot/nix-build") | .link'
  # URL shape: /#/builders/<BUILDER_ID>/builds/<BUILD_ID>
  # (Both buildbot/nix-build and buildbot/nix-eval share this URL — the
  # parent nix-eval build contains both phases' logs as separate steps.)

Privacy: captured logs may include build output, worker names, store
paths, and buildbot-masked token references (e.g. <github-token-N>).
Review before sharing publicly.
HELP
    exit 0
    ;;
esac

if [ "$#" -lt 2 ]; then
  echo "Error: BUILDER_ID and BUILD_ID required" >&2
  echo "Try 'buildbot-logs --help' for more information." >&2
  exit 2
fi

builder="$1"
build="$2"
host="${BUILDBOT_SSH_HOST:-magnetite.zt}"
include_hidden="${BUILDBOT_INCLUDE_HIDDEN:-0}"
ssh_bin="${BUILDBOT_SSH_BIN:-ssh}"

case "$builder$build" in
  *[!0-9]*|"")
    echo "Error: BUILDER_ID and BUILD_ID must be positive integers" >&2
    exit 2
    ;;
esac

echo "Fetching logs for build $builder/$build from $host..." >&2

"$ssh_bin" -T "$host" \
  "BUILDER=$builder BUILD=$build INCLUDE_HIDDEN=$include_hidden bash -s" \
<<'REMOTE_SCRIPT'
set -euo pipefail

API=http://127.0.0.1:8010/api/v2
PW=$(sudo -n bash -c 'cat /run/secrets.d/*/vars/buildbot-http-basic-auth-password/secret' 2>/dev/null) || {
  echo "Error: failed to read buildbot http basic auth password on $(hostname)" >&2
  exit 3
}

api() { curl -fsS -u "buildbot:$PW" "$API/$1"; }

dump_build_steps_and_logs() {
  local b="$1" n="$2"
  local steps_json
  echo "=== STEPS ==="
  steps_json=$(api "builders/$b/builds/$n/steps")
  echo "$steps_json" | jq -r '.steps[]
    | "\(.number)\t\(.name)\t\(.state_string // "")\tstepid=\(.stepid)\thidden=\(.hidden // false)"'
  echo

  echo "$steps_json" | jq -c '.steps[]' | while read -r step; do
    number=$(echo "$step"  | jq -r '.number')
    name=$(echo "$step"    | jq -r '.name')
    stepid=$(echo "$step"  | jq -r '.stepid')
    hidden=$(echo "$step"  | jq -r '.hidden // false')
    if [ "$hidden" = "true" ] && [ "$INCLUDE_HIDDEN" != "1" ]; then continue; fi
    logs_json=$(api "steps/$stepid/logs" || echo '{"logs":[]}')
    echo "$logs_json" | jq -c '.logs[]?' | while read -r log; do
      logid=$(echo "$log"     | jq -r '.logid')
      logname=$(echo "$log"   | jq -r '.name')
      num_lines=$(echo "$log" | jq -r '.num_lines // 0')
      echo "=== STEP $number: $name / LOG: $logname ($num_lines lines) ==="
      api "logs/$logid/raw" || echo "(log fetch failed)"
      echo
    done
  done
}

echo "=== BUILD $BUILDER/$BUILD ==="
parent_json=$(api "builders/$BUILDER/builds/$BUILD") || {
  echo "Error: build $BUILDER/$BUILD not found or API unreachable" >&2
  exit 4
}
echo "$parent_json" | jq '.builds[0]'
echo

dump_build_steps_and_logs "$BUILDER" "$BUILD"

parent_buildid=$(echo "$parent_json" | jq -r '.builds[0].buildid // empty')
if [ -n "$parent_buildid" ]; then
  triggered_json=$(api "builds/$parent_buildid/triggered_builds" || echo '{"builds":[]}')
  echo "$triggered_json" | jq -c '.builds[]?' | while read -r child; do
    cb_builder=$(echo "$child" | jq -r '.builderid')
    cb_number=$(echo "$child"  | jq -r '.number')
    cb_buildid=$(echo "$child" | jq -r '.buildid')
    effect_name=$(api "builds/$cb_buildid/properties" \
      | jq -r '.properties[0]."virtual_builder_name"[0] // ""' 2>/dev/null || echo "")
    echo "=== CHILD BUILD $cb_builder/$cb_number  ($effect_name) ==="
    dump_build_steps_and_logs "$cb_builder" "$cb_number"
  done
fi
REMOTE_SCRIPT

echo "Done." >&2
