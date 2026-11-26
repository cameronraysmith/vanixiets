# omnigraph-probe: omnigraph-server's state for node_exporter's textfile
# collector. omnigraph-server serves no metrics; its public /readyz reports
# readiness and graph counts by state, and the bearer-token routes
# `GET /graphs` (action `graph_list`) and `GET /graphs/<graph>/snapshot`
# (action `read` on `main`) report each graph's state, entity counts,
# manifest version and storage format (omnigraph 0.16.0,
# crates/omnigraph-server/src/handlers.rs).
#
# Where services.omnigraph.enable is set on a host running node_exporter,
# omnigraph-probe.service runs every 60 s as node_exporter's user and writes
# omnigraph.prom into the host's one textfile directory
# (./node-exporter-textfile.nix) by write-then-rename:
# - always: vanixiets_omnigraph_ready, 1 only when /readyz answers
#   `ready: true` and 0 otherwise, the server down included;
#   vanixiets_omnigraph_graphs{state} for served, ready, loading and
#   blocked, while /readyz answers; and
#   vanixiets_omnigraph_start_to_ready_seconds, from omnigraph-server's main
#   process start to the end of its start job, whose ExecStartPost waits for
#   readiness, while the unit is active;
# - with the `monitor` actor's token (services.omnigraph.extraBearerTokenFiles):
#   vanixiets_omnigraph_graph_entities, _graph_manifest_version and
#   _graph_storage_format per ready graph, a graph whose read fails left out;
# - on a local root: vanixiets_omnigraph_dataset_used_bytes, _quota_bytes and
#   _snapshots of the ZFS dataset mounted at the root's parent, and
#   vanixiets_omnigraph_lock_recoveries_total from
#   flake.lib.omnigraphProbe.lockRecoveriesFile, 0 while that file is absent.
# The series names are in nodeExporterKeep; the assertion keeps the
# keep-list, the textfile collector and the writer from drifting apart from
# the probe. fleet-alert's OmnigraphNotServing reads the first two series,
# HostProbeStale reports a probe that stops writing, and the Perses view
# dashboard-omnigraph.json shows them all.
{ config, lib, ... }:
let
  inherit (config.flake) modules;
  schema = config.flake.lib.otelCollectorSchema;
  inherit (config.flake.lib.nodeExporterTextfile) flag;
  inherit (config.flake.lib.omnigraphServer) bindTargetOf localRootOf;

  writer = "omnigraph";
  monitorActor = "monitor";
  credential = "monitor-token";
  lockRecoveriesFile = "/var/lib/omnigraph-metrics/lock-recoveries";
  seriesNames = [
    "vanixiets_omnigraph_ready"
    "vanixiets_omnigraph_graphs"
    "vanixiets_omnigraph_start_to_ready_seconds"
    "vanixiets_omnigraph_graph_entities"
    "vanixiets_omnigraph_graph_manifest_version"
    "vanixiets_omnigraph_graph_storage_format"
    "vanixiets_omnigraph_dataset_used_bytes"
    "vanixiets_omnigraph_dataset_quota_bytes"
    "vanixiets_omnigraph_dataset_snapshots"
    "vanixiets_omnigraph_lock_recoveries_total"
  ];

  probe =
    pkgs:
    {
      url,
      localRoot,
      zfs,
      systemd,
    }:
    let
      parent = builtins.dirOf localRoot;
      # A root under the DynamicUser state directory /var/lib/omnigraph is
      # reached through systemd's symlink to /var/lib/private/omnigraph, so
      # its dataset may be mounted at either path.
      mountpoints = [
        parent
      ]
      ++ lib.optional (lib.hasPrefix "/var/lib/omnigraph/" parent) (
        "/var/lib/private/omnigraph/" + lib.removePrefix "/var/lib/omnigraph/" parent
      );
    in
    pkgs.writeShellApplication {
      name = "omnigraph-probe";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.curl
        pkgs.gawk
        pkgs.jq
        systemd
      ]
      ++ lib.optional (localRoot != null) zfs;
      text = ''
        out=$1
        url=${lib.escapeShellArg url}
        scratch=$(mktemp -d)
        trap 'rm -rf -- "$scratch"' EXIT
        series() { # <name> <type> <help>
          printf '# HELP %s %s\n# TYPE %s %s\n' "$1" "$3" "$1" "$2"
        }

        exec 3>"$out.tmp"

        ready=0
        contract=
        if curl --silent --max-time 5 --dump-header "$scratch/headers" --output "$scratch/readyz" "$url/readyz" \
          && counts=$(jq -er '
            [.ready, .served_graph_count, .ready_graph_count, .loading_graph_count, .blocked_graph_count]
            | if (.[0] | type) == "boolean" and (.[1:] | all(type == "number"))
              then map(tostring) | join(" ")
              else error("not a readiness report")
              end' "$scratch/readyz" 2>/dev/null); then
          read -r answer served ready_count loading blocked <<<"$counts"
          [ "$answer" = true ] && ready=1
          # Every answer names the HTTP contract the bearer-token routes require.
          contract=$(tr -d '\r' <"$scratch/headers" | awk -F': *' 'tolower($1) == "omnigraph-http-api" { print $2 }')
          {
            series vanixiets_omnigraph_graphs gauge "omnigraph-server's graphs by state, from /readyz."
            printf 'vanixiets_omnigraph_graphs{state="%s"} %s\n' \
              served "$served" ready "$ready_count" loading "$loading" blocked "$blocked"
          } >"$scratch/graphs"
        fi
        series vanixiets_omnigraph_ready gauge "1 when omnigraph-server's /readyz answers ready, else 0." >&3
        echo "vanixiets_omnigraph_ready $ready" >&3
        [ ! -e "$scratch/graphs" ] || cat "$scratch/graphs" >&3

        active=""
        main_start=""
        active_enter=""
        while IFS='=' read -r key value; do
          case $key in
            ActiveState) active=$value ;;
            ExecMainStartTimestampMonotonic) main_start=$value ;;
            ActiveEnterTimestampMonotonic) active_enter=$value ;;
          esac
        done < <(systemctl show omnigraph-server.service \
          -p ActiveState -p ExecMainStartTimestampMonotonic -p ActiveEnterTimestampMonotonic || true)
        if [ "$active" = active ] && [ "''${main_start:-0}" -gt 0 ] && [ "''${active_enter:-0}" -ge "$main_start" ]; then
          series vanixiets_omnigraph_start_to_ready_seconds gauge "Seconds from omnigraph-server's main process start to the end of its start job." >&3
          awk -v s="$main_start" -v e="$active_enter" \
            'BEGIN { printf "vanixiets_omnigraph_start_to_ready_seconds %.3f\n", (e - s) / 1000000 }' >&3
        fi

        token_file="''${CREDENTIALS_DIRECTORY:-}/${credential}"
        if [ -n "$contract" ] && [ -n "''${CREDENTIALS_DIRECTORY:-}" ] && [ -r "$token_file" ]; then
          token=$(cat -- "$token_file")
          token=''${token//\\/\\\\}
          token=''${token//\"/\\\"}
          api() { # <path>; the token reaches curl in a config on stdin, never its argv
            printf 'header = "Authorization: Bearer %s"\n' "$token" \
              | curl --config - --silent --fail --max-time 10 \
                --header "Omnigraph-Http-Api: $contract" "$url$1"
          }
          : >"$scratch/entities"
          : >"$scratch/versions"
          : >"$scratch/formats"
          if list=$(api /graphs) \
            && graphs=$(jq -er '.graphs | map(select(.state == "ready") | .graph_id) | .[]' <<<"$list"); then
            while read -r graph; do
              [ -n "$graph" ] || continue
              if snapshot=$(api "/graphs/$graph/snapshot") \
                && lines=$(jq -er --arg graph "$graph" '
                  [(.datasets | map(.entity_count) | add // 0), .graph_manifest_version, .internal_schema_version] as $v
                  | if ($v | all(type == "number")) then
                      ($graph | tojson) as $g
                      | "vanixiets_omnigraph_graph_entities{graph=\($g)} \($v[0])",
                        "vanixiets_omnigraph_graph_manifest_version{graph=\($g)} \($v[1])",
                        "vanixiets_omnigraph_graph_storage_format{graph=\($g)} \($v[2])"
                    else error("not a snapshot") end' <<<"$snapshot" 2>/dev/null); then
                sed -n 1p <<<"$lines" >>"$scratch/entities"
                sed -n 2p <<<"$lines" >>"$scratch/versions"
                sed -n 3p <<<"$lines" >>"$scratch/formats"
              fi
            done <<<"$graphs"
          fi
          if [ -s "$scratch/entities" ]; then
            {
              series vanixiets_omnigraph_graph_entities gauge "Entities in a graph's main branch, summed over its datasets."
              cat "$scratch/entities"
              series vanixiets_omnigraph_graph_manifest_version gauge "The graph manifest version of a graph's main branch."
              cat "$scratch/versions"
              series vanixiets_omnigraph_graph_storage_format gauge "The storage format (internal schema version) a graph's main branch is stamped at."
              cat "$scratch/formats"
            } >&3
          fi
        fi
        ${lib.optionalString (localRoot != null) ''
          if datasets=$(zfs list -H -p -t filesystem -o name,mountpoint,used,quota 2>/dev/null) \
            && dataset=$(awk -F'\t' ${
              lib.escapeShellArg (
                lib.concatMapStringsSep " || " (m: "$2 == \"${m}\"") mountpoints
                + " { print $1 \"\\t\" $3 \"\\t\" $4; exit }"
              )
            } <<<"$datasets") \
            && [ -n "$dataset" ]; then
            IFS=$'\t' read -r name used quota <<<"$dataset"
            if snapshots=$(zfs list -H -t snapshot -d 1 -o name "$name" 2>/dev/null | wc -l); then
              {
                series vanixiets_omnigraph_dataset_used_bytes gauge "Bytes used by the dataset holding the local root, snapshots included."
                echo "vanixiets_omnigraph_dataset_used_bytes $used"
                series vanixiets_omnigraph_dataset_quota_bytes gauge "The quota of the dataset holding the local root, 0 for none."
                echo "vanixiets_omnigraph_dataset_quota_bytes $quota"
                series vanixiets_omnigraph_dataset_snapshots gauge "Snapshots of the dataset holding the local root."
                echo "vanixiets_omnigraph_dataset_snapshots $snapshots"
              } >&3
            fi
          fi
          recoveries=0
          if [ -e ${lockRecoveriesFile} ]; then
            recoveries=$(cat ${lockRecoveriesFile} 2>/dev/null || true)
          fi
          if [[ $recoveries =~ ^[0-9]+$ ]]; then
            series vanixiets_omnigraph_lock_recoveries_total counter "Stale serve locks omnigraph-server's start has cleared on this host." >&3
            echo "vanixiets_omnigraph_lock_recoveries_total $recoveries" >&3
          fi
        ''}
        exec 3>&-
        mv -f -- "$out.tmp" "$out"
      '';
    };

  module =
    { config, pkgs, ... }:
    let
      cfg = config.services.omnigraph;
      node = config.services.prometheus.exporters.node;
      directory = config.vanixiets.nodeExporter.textfileDirectory;
      tokenFile = cfg.extraBearerTokenFiles.${monitorActor} or null;
      program = probe pkgs {
        url = "http://${bindTargetOf cfg.bindAddress cfg.port}";
        localRoot = localRootOf cfg.storageUri;
        zfs = config.boot.zfs.package;
        systemd = config.systemd.package;
      };
    in
    {
      config = lib.mkIf (cfg.enable && node.enable) {
        assertions = [
          {
            assertion =
              lib.all (name: lib.elem name schema.nodeExporterKeep) seriesNames
              && lib.elem writer config.vanixiets.nodeExporter.textfileWriters
              && lib.elem "${flag}=${directory}" node.extraFlags;
            message = "omnigraph-probe: node_exporter must run its textfile collector on ${directory} with ${writer} among vanixiets.nodeExporter.textfileWriters, and nodeExporterKeep must keep ${lib.concatStringsSep ", " seriesNames}, or OmnigraphNotServing and the omnigraph view never see the server.";
          }
        ];

        vanixiets.nodeExporter.textfileWriters = [ writer ];

        # node_exporter's own user writes into the directory node_exporter
        # reads: a DynamicUser's files would sit under /run/private, which
        # node_exporter cannot traverse (./magnetite-memory-budget.nix).
        systemd.services.omnigraph-probe = {
          description = "omnigraph-server's readiness and graphs for node_exporter's textfile collector";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${lib.getExe program} ${directory}/${writer}.prom";
            User = node.user;
            Group = node.group;
            LoadCredential = lib.optional (tokenFile != null) "${credential}:${tokenFile}";
            ReadWritePaths = [ directory ];
            UMask = "0022";
            MemoryMax = "32M";
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
          };
        };

        systemd.timers.omnigraph-probe = {
          description = "Every minute: omnigraph-server's readiness and graphs";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "1min";
            OnUnitActiveSec = "60s";
            AccuracySec = "5s";
          };
        };
      };
    };
in
{
  flake.lib.omnigraphProbe = {
    inherit
      seriesNames
      writer
      monitorActor
      lockRecoveriesFile
      probe
      ;
  };

  flake.modules.nixos.omnigraph-probe = module;
  flake.modules.nixos.omnigraph.imports = [ modules.nixos.omnigraph-probe ];
}
