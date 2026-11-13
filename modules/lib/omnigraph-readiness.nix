# Readiness probe for omnigraph-server, run as the unit's ExecStartPost.
#
# omnigraph-server binds its listener once configuration and authorization
# are valid, then opens every applied graph, answering /readyz with 503 until
# all of them have finished loading. A boot failure (missing or unapplied
# state, a held admission lock, a strict --require-all-graphs refusal, every
# graph failing) exits the process: there is no retry loop. systemd still
# waits for a running ExecStartPost after the main process has died, so a
# probe that only polls the endpoint holds the start job open for its whole
# timeout (the 15-minute switch stall a fresh storage root used to cause).
# This probe instead stops at the first conclusive answer:
#
# - $MAINPID (set by systemd for Type=simple) names a process that is gone:
#   the server exited during startup and will never answer.
# - /readyz answers 200 after loading with a graph blocked, or with fewer
#   registered graphs than were declared: graphs are opened only at startup,
#   so waiting cannot fix either.
# - /readyz answers 200 with ready true, nothing loading or blocked and the
#   expected graphs (or no expectation): ready.
#
# A 503 (loading or draining) or a 200 with ready false is transient, as is no
# answer; the probe polls every 2 seconds until `timeout` seconds have passed.
# `url` is the server's base URL without a trailing slash. /readyz is public
# and needs no Omnigraph-Http-Api header. The fields read are omnigraph's
# ReadinessOutput (ready, served_graph_count, loading_graph_count,
# blocked_graph_count); served_graph_count counts every registered graph,
# blocked ones included. An applied revision with fewer graphs than declared
# (an empty cluster included) boots and passes /readyz, which is why
# expectedGraphCount exists; leave it null when the declared graph set does
# not have to be served in full.
{ lib, ... }:
{
  flake.lib.omnigraphReadinessProbe =
    pkgs:
    {
      url,
      expectedGraphCount ? null,
      timeout,
    }:
    pkgs.writeShellApplication {
      name = "omnigraph-server-wait-ready";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.curl
        pkgs.jq
      ];
      text = ''
        url=${lib.escapeShellArg "${url}/readyz"}
        deadline=$(( $(date +%s) + ${toString timeout} ))
        while true; do
          if [ -n "''${MAINPID:-}" ] && ! kill -0 "$MAINPID" 2>/dev/null; then
            echo "omnigraph-server exited during startup before serving; see \`journalctl -u omnigraph-server\`. A fresh or never-applied storage root needs \`systemctl restart omnigraph-cluster-apply\` (or the bootstrap unit) before the server can start, and an admission lock a direct writer retained (\`state_lock_held\`) needs \`omnigraph-cluster force-unlock <LOCK_ID>\`." >&2
            exit 1
          fi
          if body=$(curl --fail --silent --max-time 5 "$url"); then
            if ! fields=$(printf '%s' "$body" | jq -er '
              [.ready, .served_graph_count, .loading_graph_count, .blocked_graph_count]
              | if (.[0] | type) == "boolean" and (.[1:] | all(type == "number"))
                then map(tostring) | join(" ")
                else error("malformed")
                end' 2>/dev/null); then
              printf 'omnigraph-server answered %s with a body that is not a readiness report: %s\n' "$url" "$body" >&2
              exit 1
            fi
            read -r ready ${
              if expectedGraphCount == null then "_" else "served"
            } loading blocked <<<"$fields"
            if [ "$loading" -eq 0 ] && [ "$blocked" -gt 0 ]; then
              printf "omnigraph-server finished startup with %s blocked graph(s) and will not open them until it restarts; see \`journalctl -u omnigraph-server\` and the blocked entries' \`failure\` in an authorized \`GET /graphs\`.\n" \
                "$blocked" >&2
              exit 1
            fi
            if [ "$ready" = true ] && [ "$loading" -eq 0 ]; then
              ${lib.optionalString (expectedGraphCount != null) ''
                if [ "$served" -lt ${toString expectedGraphCount} ]; then
                  printf "omnigraph-server serves %s of %s declared graphs. Graphs are opened only at startup, so waiting will not help: run \`systemctl restart omnigraph-cluster-apply\` (or the bootstrap unit) to apply them, then restart omnigraph-server.\n" \
                    "$served" '${toString expectedGraphCount}' >&2
                  exit 1
                fi
              ''}
              exit 0
            fi
          fi
          if [ "$(date +%s)" -ge "$deadline" ]; then
            printf 'omnigraph-server did not answer %s within %s seconds\n' \
              "$url" '${toString timeout}' >&2
            curl --fail --silent --show-error --max-time 5 --output /dev/null "$url" || true
            exit 1
          fi
          sleep 2
        done
      '';
    };
}
