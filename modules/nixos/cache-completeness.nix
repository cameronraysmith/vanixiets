# Cache completeness on magnetite (F81): every output of a build that
# reached the default branch, recorded as built or found in the store
# (succeeded, skipped_local), must be served by the public cache; those are
# the outputs deploys use. Until nixbot-upload-local-outputs.patch, a
# skipped_local attribute was never uploaded, and 383 x86_64-linux check
# outputs of the week to 2026-11-19 were missing with nothing noticing.
#
# A change usually lands by fast-forward: the default branch's push reuses
# the pull request's (or gitea-mq batch's) build by tree hash, and nixbot
# then moves that build's row to the default branch and clears its
# pr_number (orchestrator.py, get_or_create_build), keeping its finished_at.
# So `pr_number IS NULL AND branch = default_branch` selects exactly the
# builds that reached the default branch, run there or reused; build 2820
# (#2726) reads branch main, no pr_number. A build that never landed is
# left out.
#
# cache-completeness.service, hourly, reads nixbot's database as nixbot in a
# read-only transaction and requests the narinfo of the newest `limit`
# distinct outputs of the builds finished in its window, through the public
# cache URL (services.niks3.cacheUrl, served by the bucket's CDN, so
# niks3-server answers none of it). It fails, and observability-notify posts
# FAILED to fleet-alerts, when any of them is not served (anything but 200),
# and lists them in its journal. One build has about 300 distinct outputs and
# the window held at most 1,182 in the week to 2026-11-19, so `limit` covers
# the whole window; should the window outgrow it, the run says so and checks
# the newest `limit`.
#
# Window: builds that finished more than `settle` ago, so an output whose
# upload is still queued is not flagged (the patch queues a build's skipped
# outputs when its attributes are done, and nixbot gives one upload an
# hour), and within the last day, so a miss keeps the unit failed for a day
# unless it is uploaded. History: on its first run the unit only records the
# time in its state directory, and later runs consider only builds finished
# after it, so the misses from before the patch do not page; drop
# /var/lib/cache-completeness/since to move that point.
# checks.x86_64-linux.cache-completeness runs it against nixbot's real
# schema and a fixture cache with a missing narinfo.
{ config, lib, ... }:
let
  inherit (config.flake) modules;

  # The probe: SINCE_FILE CACHE_URL. psql connects through the PG*
  # environment.
  probe =
    {
      pkgs,
      postgresql,
      limit ? 2000,
      settle ? "1 hour",
    }:
    pkgs.writeShellApplication {
      name = "cache-completeness";
      runtimeInputs = [
        postgresql
        pkgs.coreutils
        pkgs.curl
        pkgs.gnugrep
      ];
      text = ''
        since_file=$1
        cache_url=$2
        if [ ! -s "$since_file" ]; then
          date -u +%Y-%m-%dT%H:%M:%SZ > "$since_file"
          echo "first run: considering attributes finished after $(cat "$since_file")"
          exit 0
        fi
        since=$(cat "$since_file")
        paths=$(PGOPTIONS="-c default_transaction_read_only=on" psql -X -q -A -t -v ON_ERROR_STOP=1 \
          -v since="$since" -f ${pkgs.writeText "cache-completeness.sql" ''
            SELECT out FROM (
              SELECT DISTINCT ON (a.outputs->>'out') a.outputs->>'out' AS out, b.finished_at
              FROM build_attributes AS a
              INNER JOIN builds AS b ON b.id = a.build_id
              INNER JOIN projects AS p ON p.id = b.project_id
              WHERE a.status IN ('succeeded', 'skipped_local')
                AND a.outputs->>'out' IS NOT NULL
                AND b.pr_number IS NULL
                AND b.branch = p.default_branch
                AND b.finished_at > greatest(:'since'::timestamptz, now() - interval '1 day')
                AND b.finished_at < now() - interval '${settle}'
              ORDER BY a.outputs->>'out', b.finished_at DESC
            ) AS o
            ORDER BY finished_at DESC
            LIMIT ${toString (limit + 1)};
          ''})
        total=$(grep -c . <<< "$paths" || true)
        if [ "$total" -gt ${toString limit} ]; then
          echo "the window holds more than ${toString limit} outputs; checking the newest ${toString limit}"
          paths=$(head -n ${toString limit} <<< "$paths")
        fi
        checked=0
        missing=0
        while read -r path; do
          [ -n "$path" ] || continue
          name=''${path#/nix/store/}
          code=$(curl -sS -o /dev/null -I --retry 2 --max-time 20 -w '%{http_code}' \
            "$cache_url/''${name%%-*}.narinfo" || true)
          checked=$((checked + 1))
          if [ "$code" != 200 ]; then
            echo "missing $code $path"
            missing=$((missing + 1))
          fi
        done <<< "$paths"
        echo "checked $checked outputs of builds finished after $since, $missing not served by $cache_url"
        [ "$missing" -eq 0 ]
      '';
    };

  module =
    {
      config,
      pkgs,
      ...
    }:
    {
      config = lib.mkIf (config.services.nixbot.enable && config.services.niks3.enable) {
        systemd.services.cache-completeness = {
          description = "Outputs nixbot built or found in the store are served by the cache";
          after = [
            "postgresql.service"
            "network-online.target"
          ];
          wants = [ "network-online.target" ];
          environment = {
            PGHOST = "/run/postgresql";
            PGDATABASE = "nixbot";
          };
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${
              lib.getExe (probe {
                inherit pkgs;
                postgresql = config.services.postgresql.package;
              })
            } /var/lib/cache-completeness/since ${config.services.niks3.cacheUrl}";
            # nixbot's own role, peer-authenticated; every transaction is
            # read-only.
            User = "nixbot";
            Group = "nixbot";
            StateDirectory = "cache-completeness";
            MemoryMax = "64M";
            TimeoutStartSec = "15min";
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
          };
        };

        systemd.timers.cache-completeness = {
          description = "Hourly: outputs nixbot built or found in the store are served by the cache";
          wantedBy = [ "timers.target" ];
          timerConfig.OnCalendar = "*:23 UTC";
        };
      };
    };
in
{
  flake.lib.cacheCompleteness.probe = probe;
  flake.modules.nixos.cache-completeness = module;
  flake.modules.nixos.nixbot.imports = [ modules.nixos.cache-completeness ];
}
