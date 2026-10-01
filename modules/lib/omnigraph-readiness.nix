# Readiness probe for omnigraph-server, run as the unit's ExecStartPost.
#
# omnigraph-server loads the cluster ledger and opens every applied graph
# before it binds its listener, and any failure there exits the process
# within seconds without ever binding: there is no retry loop and no
# not-ready serving state. systemd still waits for a running ExecStartPost
# after the main process has died, so a probe that only polls the endpoint
# holds the start job open for its whole timeout (the 15-minute switch stall
# a fresh storage root used to cause). This probe instead stops at the first
# conclusive answer:
#
# - $MAINPID (set by systemd for Type=simple) names a process that is gone:
#   the server exited during startup and will never answer.
# - /readyz answers 200 but reports graphs quarantined during startup, or
#   serves fewer graphs than were declared: graphs are opened only at boot,
#   so waiting cannot fix either.
# - /readyz answers 200 with ready true, nothing quarantined and the expected
#   graphs (or no expectation): ready.
#
# A 503 (draining) or a 200 with ready false is transient, as is no answer;
# the probe polls every 2 seconds until `timeout` seconds have passed. `url`
# is the server's base URL without a trailing slash. The fields read are
# omnigraph's ReadinessOutput (ready, served_graph_count,
# quarantined_graph_count). A root imported but never applied boots with zero
# graphs and passes /readyz, which is why expectedGraphCount exists; leave it
# null when the declared graph set does not have to be served in full.
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
            echo "omnigraph-server exited during startup before serving; see \`journalctl -u omnigraph-server\`. A fresh or never-applied storage root needs \`systemctl restart omnigraph-cluster-apply\` (or the bootstrap unit) before the server can start." >&2
            exit 1
          fi
          if body=$(curl --fail --silent --max-time 5 "$url"); then
            if ! fields=$(printf '%s' "$body" | jq -er '
              [.ready, .served_graph_count, .quarantined_graph_count]
              | if (.[0] | type) == "boolean" and (.[1] | type) == "number" and (.[2] | type) == "number"
                then map(tostring) | join(" ")
                else error("malformed")
                end' 2>/dev/null); then
              printf 'omnigraph-server answered %s with a body that is not a readiness report: %s\n' "$url" "$body" >&2
              exit 1
            fi
            read -r ready ${if expectedGraphCount == null then "_" else "served"} quarantined <<<"$fields"
            if [ "$quarantined" -gt 0 ]; then
              printf "omnigraph-server quarantined %s graph(s) during startup and will not serve them until it restarts; see \`journalctl -u omnigraph-server\` ('graph quarantined during startup' lines) and \`omnigraph-cluster status\`.\n" \
                "$quarantined" >&2
              exit 1
            fi
            if [ "$ready" = true ]; then
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
