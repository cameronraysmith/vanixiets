# R3.1 and R1.2 over magnetite's collector (design D11; tasks.md 4.4).
#
# R3.1 reads the evaluated collector configuration, node_exporter, the
# owner-alias transform and the failure-notifier wiring; R1.2 requires the
# exponential-histogram conversion while the store is below 1.3.0 (ADR-001).
# Each mutant edits the evaluated input and must produce a non-empty failure
# list (modules/checks/omnigent-environment.nix pattern), so a successful
# build shows every mutant failing. The derivation depends on the validated
# configuration file, so building the check runs `otelcol-contrib validate`
# on what magnetite deploys, and it runs the unknown-key mutant through the
# same validator, which must reject it. Of ADR-003's five R3.1 mutants
# (A3:233), the darwin node_exporter one belongs to S5; the other four are
# here.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      magnetite = self.nixosConfigurations.magnetite.config;
      collector = magnetite.services.opentelemetry-collector;

      mib = n: n * 1024 * 1024;

      # Unmeasured estimate of magnetite's `fleet` export rate: about 2000
      # series (ADR-004's ~800 host-level series per NixOS host plus the
      # scraped service endpoints) at 128 bytes per OTLP number point with its
      # resource and attribute overhead, one point per minute. The deployment
      # measurement (logs/s1-evidence/8.5-queue-rate.log) replaces it.
      fleetBytesPerMinute = 256000;

      # The units the failure path wires (design "Failure path"). A literal,
      # so dropping a unit from services.observability-notify.units fails.
      notifiedUnits = [
        "greptimedb"
        "greptimedb-schema"
        "opentelemetry-collector"
        "zfs-assert-root-docker-noautosnap"
        "zfs-assert-root-greptimedb-noautosnap"
        "zfs-assert-root-nix-noautosnap"
        "zfs-assert-root-podman-noautosnap"
        "zfs-set-root-greptimedb-quota"
        "zfs-set-root-greptimedb-reservation"
        "zfs-set-root-home-reservation"
        "zfs-set-root-nix-quota"
        "zfs-set-root-nixos-reservation"
      ];

      sixProcessAttributes = [
        "process.pid"
        "process.parent_pid"
        "process.command"
        "process.command_line"
        "process.executable.path"
        "process.owner"
      ];

      expectedScrapeTargets = [
        "127.0.0.1:3002"
        "127.0.0.1:4000"
        "127.0.0.1:5752"
        "127.0.0.1:9100"
        "127.0.0.1:9180"
        "127.0.0.1:9993"
      ];

      expectedNodeFlags = [
        "--collector.disable-defaults"
        "--collector.zfs"
        "--collector.vmstat"
        "--collector.vmstat.fields=^oom_kill$"
      ];

      isLoopback =
        s:
        builtins.match "(https?://)?(127\\.[0-9]+\\.[0-9]+\\.[0-9]+|\\[::1]|localhost)(:[0-9]+)?(/.*)?" s
        != null;

      # Every `endpoint` string anywhere under a component section.
      collectEndpoints =
        value:
        if builtins.isAttrs value then
          lib.concatLists (
            lib.mapAttrsToList (
              name: inner:
              if name == "endpoint" && builtins.isString inner then [ inner ] else collectEndpoints inner
            ) value
          )
        else if builtins.isList value then
          lib.concatMap collectEndpoints value
        else
          [ ];

      # systemd unit patterns as regular expressions over attribute names.
      unitRegex = pattern: builtins.replaceStrings [ "." "*" ] [ "\\." ".*" ] pattern;
      matchesAllowList =
        patterns: name: lib.any (p: builtins.match (unitRegex p) "${name}.service" != null) patterns;

      resolvedHook = "-\\+/nix/store/[a-z0-9]{32}-observability-notify-resolved %n";

      input = {
        settings = collector.settings;
        overrides = collector.validateConfigOverrides;
        collectorService = magnetite.systemd.services.opentelemetry-collector.serviceConfig;
        node = magnetite.services.prometheus.exporters.node;
        nodeService = magnetite.systemd.services.prometheus-node-exporter.serviceConfig;
        nginxStatusPage = magnetite.services.nginx.statusPage;
        zerotierMetrics = magnetite.services.zerotierone.localConf.settings.enableMetrics or false;
        services = magnetite.systemd.services;
        notifyUnits = magnetite.services.observability-notify.units;
        schema = self.lib.otelCollectorSchema;
        storeVersion = magnetite.services.greptimedb.package.version;
      };

      failures =
        i:
        let
          s = i.settings;
          r = s.receivers;
          p = s.processors;
          e = s.exporters;
          pipelines = s.service.pipelines;
          check = name: ok: lib.optional (!ok) name;
          dbs = i.schema.databases;
          exporterNames = map (db: "otlp_http/${db}") dbs;
          process = r."host_metrics/process".scrapers.process;
          memory = r."host_metrics/memory".scrapers;
          promTargets = lib.concatMap (
            name:
            lib.concatMap (
              job: lib.concatMap (sc: sc.targets) job.static_configs
            ) r.${name}.config.scrape_configs
          ) (builtins.filter (lib.hasPrefix "prometheus") (builtins.attrNames r));
          nodeJob = lib.findFirst (job: job.job_name == "node") null r.prometheus.config.scrape_configs;
          queueSizes = map (n: e.${n}.sending_queue.queue_size or 0) exporterNames;
          hostUnits = builtins.attrNames i.services;
          owners = lib.concatMap (
            name:
            let
              m = builtins.match "omnigent-host-(.+)" name;
            in
            lib.optional (m != null) (builtins.head m)
          ) hostUnits;
          aliasStatements = p."transform/omnigent-alias".metric_statements or [ ];
          aliasStatement =
            owner:
            ''set(resource.attributes["systemd.unit.name"], "omnigent-host-${i.schema.ownerAliases.${owner}}.service") where resource.attributes["systemd.unit.name"] == "omnigent-host-${owner}.service"'';
          zerotierJobs = map (job: builtins.removeAttrs job [ "authorization" ]) (
            r."prometheus/zerotier".config.scrape_configs or [ ]
          );
          overrideParts = map (builtins.match "([^=]*)=(.*)") i.overrides;
          unitWired =
            name:
            let
              u =
                i.services.${name} or {
                  unitConfig = { };
                  serviceConfig = { };
                };
            in
            (u.unitConfig.OnFailure or null) == [ "observability-notify@%n.service" ]
            && lib.any (hook: builtins.match resolvedHook hook != null) (
              lib.toList (u.serviceConfig.ExecStopPost or [ ])
            );
          notifier = i.services."observability-notify@".serviceConfig.ExecStart or "";
          exphist = p."transform/exphist".metric_statements or [ ];
        in
        lib.concatLists [
          # Loopback (R3.1; telemetry-store-interface "Scrape targets are reached on loopback").
          (check "R3.1: receiver or exporter endpoint off loopback" (
            lib.all isLoopback (collectEndpoints r ++ collectEndpoints e)
          ))
          (check "R3.1: scrape targets differ from the loopback set" (
            lib.naturalSort promTargets == expectedScrapeTargets
          ))
          (check "R3.1: nginx stub_status not collected" (
            i.nginxStatusPage && (r.nginx.endpoint or "") == "http://127.0.0.1:80/nginx_status"
          ))
          (check "R3.1: zerotierone metrics not enabled" (i.zerotierMetrics == true))
          (check "R3.1: node_exporter not on loopback" (
            i.node.enable && i.node.listenAddress == "127.0.0.1" && !i.node.openFirewall
          ))
          (check "R3.1: node_exporter collectors or envelope" (
            i.node.extraFlags == expectedNodeFlags && (i.nodeService.MemoryMax or null) == "64M"
          ))
          (check "R3.1: node_exporter keep-list" (
            nodeJob != null
            &&
              (nodeJob.metric_relabel_configs or [ ]) == [
                {
                  source_labels = [ "__name__" ];
                  regex = lib.concatStringsSep "|" i.schema.nodeExporterKeep;
                  action = "keep";
                }
              ]
          ))

          # Bounds (host-metrics-collection "Series cardinality stays bounded").
          (check "R3.1: process identity attribute enabled" (
            lib.all (a: (process.resource_attributes.${a}.enabled or true) == false) sixProcessAttributes
          ))
          (check "R3.1: process metrics other than memory usage" (
            process.metrics == {
              "process.memory.usage".enabled = true;
              "process.cpu.time".enabled = false;
              "process.disk.io".enabled = false;
              "process.memory.virtual".enabled = false;
            }
          ))
          (check "R3.1: process 64 MiB filter" (
            i.schema.process.minBytes == mib 64
            && i.schema.process.maxNames == 30
            &&
              (p."filter/process-min".metric_conditions or [ ]) == [
                ''metric.name == "process.memory.usage" and datapoint.value_int < ${toString i.schema.process.minBytes}''
              ]
            && builtins.elem "filter/process-min" pipelines."metrics/process".processors
          ))
          (check "R3.1: paging beyond usage" (
            memory.paging.metrics == {
              "system.paging.usage".enabled = true;
              "system.paging.operations".enabled = false;
              "system.paging.faults".enabled = false;
              "system.paging.utilization".enabled = false;
            }
          ))
          (check "R3.1: available memory not collected" (
            (memory.memory.metrics."system.linux.memory.available".enabled or false) == true
          ))
          (check "R3.1: systemd units differ from schema.nix" (
            r.systemd.units == i.schema.systemdUnits && r.systemd.scope == "system"
          ))
          (check "R3.1: systemd metrics" (
            r.systemd.metrics == {
              "systemd.service.restarts".enabled = true;
              "systemd.service.cpu.time".enabled = false;
            }
          ))
          (check "R3.1: more than 40 allow-listed units" (
            builtins.length i.schema.systemdUnits <= 40
            && builtins.length (builtins.filter (matchesAllowList i.schema.systemdUnits) hostUnits) <= 40
          ))
          (check "R3.1: omnigent-host owner without alias" (
            lib.all (o: i.schema.ownerAliases ? ${o} && builtins.elem (aliasStatement o) aliasStatements) owners
            && builtins.elem "transform/omnigent-alias" pipelines."metrics/host".processors
          ))
          (check "R3.1: an alias carries an owner name" (
            lib.all (alias: lib.all (o: !(lib.hasInfix o alias)) owners) (
              builtins.attrValues i.schema.ownerAliases
            )
          ))

          # Ingest (telemetry-store-interface "Ingest is OTLP over HTTP with a database header").
          (check "R3.1: a logs or traces pipeline" (
            lib.all (lib.hasPrefix "metrics/") (builtins.attrNames pipelines)
          ))
          (check "R3.1: routing table" (
            lib.all (
              db:
              lib.any (
                t:
                t.condition == ''attributes["vanixiets.database"] == "${db}"'' && t.pipelines == [ "metrics/${db}" ]
              ) s.connectors.routing.table
            ) dbs
          ))
          (check "R3.1: exporter endpoint, headers or auth" (
            lib.all (
              db:
              let
                x = e."otlp_http/${db}";
              in
              x.endpoint == "http://127.0.0.1:4000/v1/otlp"
              &&
                x.headers == {
                  "x-greptime-db-name" = db;
                  "x-greptime-otlp-metric-promote-resource-attrs" =
                    lib.concatStringsSep ";" i.schema.promotedResourceAttributes;
                }
              && x.auth.authenticator == "basicauth/store"
            ) dbs
          ))
          (check "R3.1: store credential" (
            s.extensions."basicauth/store".client_auth == {
              username = "collector";
              password_file = "/run/credentials/opentelemetry-collector.service/collector-password";
            }
          ))

          # Queue (host-metrics-collection "Collection survives a telemetry store restart").
          (check "R3.1: queue not in file_storage" (
            lib.all (
              n:
              (e.${n}.sending_queue.storage or null) == "file_storage"
              && (e.${n}.sending_queue.sizer or null) == "bytes"
              && (e.${n}.retry_on_failure.max_elapsed_time or null) == "0s"
            ) exporterNames
          ))
          (check "R3.1: queue directory" (
            lib.hasPrefix "/var/lib/opentelemetry-collector/" s.extensions.file_storage.directory
            && s.extensions.file_storage.create_directory == true
          ))
          (check "R3.1: fleet queue below 24 h" (
            (e."otlp_http/fleet".sending_queue.queue_size or 0) >= 24 * 60 * fleetBytesPerMinute
          ))
          (check "R3.1: queues at or above 512 MiB" (lib.foldl' builtins.add 0 queueSizes < mib 512))

          # Envelope (telemetry-store-interface "run inside a declared envelope").
          (check "R3.1: collector envelope" (
            p.memory_limiter.limit_mib == 384
            && builtins.head pipelines."metrics/ingress".processors == "memory_limiter"
            && (i.collectorService.MemoryMax or null) == "512M"
            && (i.collectorService.OOMScoreAdjust or null) == 300
          ))

          # Validation override: only the zerotierone job's authorization.
          (check "R3.1: validation override beyond the zerotierone authorization" (
            zerotierJobs != [ ]
            && builtins.length overrideParts == 1
            && lib.all (m: m != null) overrideParts
            &&
              builtins.elemAt (builtins.head overrideParts) 0
              == "receivers::prometheus/zerotier::config::scrape_configs"
            && builtins.fromJSON (builtins.elemAt (builtins.head overrideParts) 1) == zerotierJobs
          ))

          # Failure wiring (telemetry-store-interface "Failure notices are posted to one topic").
          (check "R3.1: notified units differ" (lib.naturalSort i.notifyUnits == notifiedUnits))
          (check "R3.1: a named unit is not wired to the notifier" (lib.all unitWired notifiedUnits))
          (check "R3.1: notifier does not post to fleet-alerts with ntfy-send" (
            lib.hasInfix "/bin/ntfy-send " notifier && lib.hasInfix " fleet-alerts" notifier
          ))

          # R1.2 (ADR-001): below 1.3.0 the store needs explicit-bucket histograms.
          (lib.optional (
            lib.versionOlder i.storeVersion "1.3.0"
            && !(
              builtins.elem "transform/exphist" pipelines."metrics/ingress".processors
              && lib.any (lib.hasPrefix "convert_exponential_histogram_to_histogram(") exphist
            )
          ) "R1.2: exponential-histogram conversion missing below store 1.3.0")
        ];

      actual = failures input;

      onSettings = update: i: i // { settings = lib.recursiveUpdate i.settings update; };

      mutants = {
        # A3:233: a receiver endpoint of 0.0.0.0:4318.
        receiverEndpointWildcard = onSettings {
          receivers.otlp.protocols.http.endpoint = "0.0.0.0:4318";
        };
        # A3:233: an exporter listenAddress of 0.0.0.0.
        exporterListenWildcard =
          i:
          i
          // {
            node = i.node // {
              listenAddress = "0.0.0.0";
            };
          };
        # A3:233: process.command_line enabled.
        commandLineEnabled = onSettings {
          receivers."host_metrics/process".scrapers.process.resource_attributes."process.command_line".enabled =
            true;
        };
        scrapeTargetOffLoopback =
          i:
          onSettings {
            receivers.prometheus.config.scrape_configs = map (
              job:
              if job.job_name == "node" then
                job // { static_configs = [ { targets = [ "10.147.17.1:9100" ]; } ]; }
              else
                job
            ) i.settings.receivers.prometheus.config.scrape_configs;
          } i;
        systemdUnitsDiverge =
          i:
          onSettings {
            receivers.systemd.units = i.settings.receivers.systemd.units ++ [ "user@*.service" ];
          } i;
        systemdUnitsOverCap =
          i:
          let
            units = i.schema.systemdUnits ++ map (n: "cap-${toString n}.service") (lib.range 1 20);
          in
          (onSettings { receivers.systemd.units = units; } i)
          // {
            schema = i.schema // {
              systemdUnits = units;
            };
          };
        ownerWithoutAlias =
          i:
          i
          // {
            schema = i.schema // {
              ownerAliases = builtins.removeAttrs i.schema.ownerAliases [ "cameron" ];
            };
          };
        queueInMemory =
          i:
          i
          // {
            settings = i.settings // {
              exporters = i.settings.exporters // {
                "otlp_http/fleet" = i.settings.exporters."otlp_http/fleet" // {
                  sending_queue = builtins.removeAttrs i.settings.exporters."otlp_http/fleet".sending_queue [
                    "storage"
                  ];
                };
              };
            };
          };
        queueUnder24h = onSettings { exporters."otlp_http/fleet".sending_queue.queue_size = mib 64; };
        queueOver512MiB = onSettings { exporters."otlp_http/fleet".sending_queue.queue_size = mib 448; };
        overrideTouchesAnotherReceiver =
          i:
          i // { overrides = i.overrides ++ [ "receivers::host_metrics/memory::collection_interval=1s" ]; };
        onFailureDropped =
          i:
          i
          // {
            services = i.services // {
              opentelemetry-collector = i.services.opentelemetry-collector // {
                unitConfig = builtins.removeAttrs i.services.opentelemetry-collector.unitConfig [ "OnFailure" ];
              };
            };
          };
        # R1.2's mutant.
        conversionRemoved = onSettings { processors."transform/exphist".metric_statements = [ ]; };
      };

      # hostmetricsreceiver ignores unknown top-level keys (receiver/hostmetricsreceiver/config.go Unmarshal, WithIgnoreUnused, v0.155.0), so the probe targets a strictly decoded component.
      unknownKeyConfig = (pkgs.formats.yaml { }).generate "otel-collector-unknown-key.yaml" (
        lib.recursiveUpdate collector.settings { processors.memory_limiter.unknown_key = true; }
      );
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        otel-collector-config =
          assert lib.assertMsg (actual == [ ]) "otel-collector-config failures: ${builtins.toJSON actual}";
          assert lib.assertMsg (lib.all (mutant: failures (mutant input) != [ ]) (lib.attrValues mutants))
            "otel-collector-config accepted a mutant: ${
              builtins.toJSON (builtins.attrNames (lib.filterAttrs (_: m: failures (m input) == [ ]) mutants))
            }";
          pkgs.runCommand "otel-collector-config"
            {
              # The configuration magnetite deploys, validated by nixpkgs'
              # module with `otelcol-contrib validate` at build time.
              validated = magnetite.system.build.opentelemetryCollectorConfig;
              passthru = { inherit failures; };
            }
            ''
              test -s "$validated"
              # A3:233: an unknown component key must be rejected by the same
              # validator with the same overrides.
              if result=$(${lib.getExe collector.package} validate --config=file:${unknownKeyConfig} ${
                lib.escapeShellArgs (map (o: "--set=${o}") collector.validateConfigOverrides)
              } 2>&1); then
                echo "otelcol-contrib validate accepted an unknown key" >&2
                exit 1
              fi
              if ! printf '%s\n' "$result" | grep -q unknown_key; then
                echo "validation failed for a reason other than the unknown key:" >&2
                printf '%s\n' "$result" >&2
                exit 1
              fi
              touch "$out"
            '';
      };
    };
}
