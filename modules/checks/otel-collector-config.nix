# R3.1 and R1.2 over magnetite's collector (design D11; tasks.md 4.4, 10.8, 10.9).
#
# R3.1 judges relations in magnetite's evaluated configuration that a
# plausible edit would break silently: every listener and scrape target on
# loopback, the unit cap on the host, owner aliases, queue sizes against the
# assumed rate, the validation override's scope, the failure-notifier wiring
# against the failure path's policy, the limiter under the unit's ceiling and
# the collector's order after the schema job. It does not copy the module's
# literals, and the process identity attributes and node_exporter's firewall
# are module assertions. R1.2 requires the exponential-histogram conversion
# while the store is below 1.3.0 (ADR-001). Each mutant edits the evaluated
# input and must produce a non-empty failure list
# (modules/checks/omnigent-environment.nix pattern). The configuration file
# itself is validated by nixpkgs' module when magnetite's toplevel builds.
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

      # The failure path's policy (design "Failure path"): every store unit,
      # every disk-share oneshot and the collector notify, so a new unit of
      # these kinds fails the check until it is listed.
      notifiedByPolicy =
        name:
        lib.hasPrefix "greptimedb" name
        || lib.hasPrefix "zfs-set-" name
        || lib.hasPrefix "zfs-assert-" name
        || name == "opentelemetry-collector";

      # ADR-004 Q12: at most 40 units may match the allow-list on one host.
      maxUnits = 40;

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

      resolvedHook = mode: "-\\+(/nix/store/[a-z0-9]{32}-observability-notify-resolved) ${mode} %n";

      input = {
        settings = collector.settings;
        overrides = collector.validateConfigOverrides;
        collectorService = magnetite.systemd.services.opentelemetry-collector.serviceConfig;
        node = magnetite.services.prometheus.exporters.node;
        services = magnetite.systemd.services;
        notifyUnits = magnetite.services.observability-notify.units;
        schema = self.lib.otelCollectorSchema;
        storeVersion = magnetite.services.greptimedb.package.version;
        notifierInterval =
          magnetite.systemd.services."observability-notify@".environment.OBSERVABILITY_NOTIFY_MIN_INTERVAL_SEC
            or null;
      };

      # The notifier magnetite deploys, built from the same function the
      # rehearsal below runs.
      deployedNotify = self.lib.observabilityNotifyScripts self.nixosConfigurations.magnetite.pkgs {
        ntfySend = lib.getExe self.nixosConfigurations.magnetite.pkgs.ntfy-send;
        stampDir = "/var/lib/observability-notify";
        hostName = "magnetite";
      };

      # The notifier's scripts against a temporary stamp directory (`$TMPDIR`
      # expands when they run) and an ntfy-send that records each post.
      ntfyStub = pkgs.writeShellScript "ntfy-send-stub" ''
        printf '%s|%s\n' "$1" "$2" >> "$NTFY_STUB_LOG"
      '';
      rehearsedNotify = self.lib.observabilityNotifyScripts pkgs {
        ntfySend = "${ntfyStub}";
        stampDir = "$TMPDIR/notify";
        hostName = "rehearsal";
      };
      notifierRehearsal =
        pkgs.runCommand "observability-notify-rehearsal"
          {
            nativeBuildInputs = [ pkgs.coreutils ];
            meta.description = "behavioural check: a crash loop yields one FAILED/RESOLVED pair per interval";
          }
          ''
            set -euo pipefail
            export NTFY_STUB_LOG="$TMPDIR/posts" OBSERVABILITY_NOTIFY_MIN_INTERVAL_SEC=900
            mkdir "$TMPDIR/notify"
            touch "$NTFY_STUB_LOG"
            unit=opentelemetry-collector.service
            # systemd's order for a crash with automatic restart: the stop
            # hook with a failed result, OnFailure's notifier, then the start.
            crash() { SERVICE_RESULT=exit-code ${rehearsedNotify.resolved} stop "$unit"; ${rehearsedNotify.failed} "$unit"; }
            start() { ${rehearsedNotify.resolved} start "$unit"; }
            expect() {
              if [ "$(cat "$NTFY_STUB_LOG")" != "$2" ]; then
                echo "FAIL: $1; posts were:" >&2
                cat "$NTFY_STUB_LOG" >&2
                exit 1
              fi
              echo "ok: $1"
            }
            failed="FAILED $unit on rehearsal|fleet-alerts"
            resolved="RESOLVED $unit on rehearsal|fleet-alerts"

            crash; start; crash; start
            expect "crash, start, crash, start within the interval posts one pair" "$failed"$'\n'"$resolved"

            mkdir -p "$TMPDIR/notify/last-failed"
            echo $(( $(date +%s) - 901 )) > "$TMPDIR/notify/last-failed/$unit"
            crash; ${rehearsedNotify.failed} "$unit"; start
            SERVICE_RESULT=success ${rehearsedNotify.resolved} stop "$unit"
            expect "a crash after the interval posts a new pair, once" "$failed"$'\n'"$resolved"$'\n'"$failed"$'\n'"$resolved"
            touch "$out"
          '';

      failures =
        i:
        let
          s = i.settings;
          r = s.receivers;
          p = s.processors;
          e = s.exporters;
          pipelines = s.service.pipelines;
          check = name: ok: lib.optional (!ok) name;
          dbs = lib.attrNames i.schema.databases;
          exporterNames = map (db: "otlp_http/${db}") dbs;
          collectorMemoryMax = builtins.match "([0-9]+)M" (i.collectorService.MemoryMax or "");
          promTargets = lib.concatMap (
            name:
            lib.concatMap (
              job: lib.concatMap (sc: sc.targets) job.static_configs
            ) r.${name}.config.scrape_configs
          ) (builtins.filter (lib.hasPrefix "prometheus") (builtins.attrNames r));
          queueSizes = map (n: e.${n}.sending_queue.queue_size or 0) exporterNames;
          hostUnits = builtins.attrNames i.services;
          owners = lib.concatMap (
            name:
            let
              m = builtins.match "omnigent-host-(.+)" name;
            in
            lib.optional (m != null) (builtins.head m)
          ) hostUnits;
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
            && lib.any (hook: builtins.match (resolvedHook "stop") hook != null) (
              lib.toList (u.serviceConfig.ExecStopPost or [ ])
            );
          hookScripts =
            mode: hooks:
            lib.unique (
              lib.concatMap (hook: lib.toList (builtins.match (resolvedHook mode) hook)) (lib.toList hooks)
            );
          # One script removes the one stamp, and systemd runs ExecStartPost
          # before ExecStopPost, so a oneshot's stop hook finds no stamp after
          # its start hook resolved and never posts RESOLVED a second time.
          startResolves =
            name:
            let
              u = i.services.${name} or { serviceConfig = { }; };
              start = hookScripts "start" (u.serviceConfig.ExecStartPost or [ ]);
            in
            start != [ ] && start == hookScripts "stop" (u.serviceConfig.ExecStopPost or [ ]);
          notifier = i.services."observability-notify@".serviceConfig.ExecStart or "";
          exphist = p."transform/exphist".metric_statements or [ ];
        in
        lib.concatLists [
          # Loopback (R3.1; telemetry-store-interface "Listeners are bound to
          # loopback only", "Scrape targets are reached on loopback").
          (check "R3.1: a receiver, exporter, scrape target or node_exporter listener off loopback" (
            lib.all isLoopback (
              collectEndpoints r ++ collectEndpoints e ++ promTargets ++ [ i.node.listenAddress ]
            )
          ))

          # Bounds (host-metrics-collection "Series cardinality stays bounded").
          (check "R3.1: the 64 MiB floor is not in the process pipeline" (
            builtins.elem "filter/process-min" pipelines."metrics/process".processors
          ))
          (check "R3.1: more than 40 allow-listed units" (
            builtins.length r.systemd.units <= maxUnits
            && builtins.length (builtins.filter (matchesAllowList r.systemd.units) hostUnits) <= maxUnits
          ))
          (check "R3.1: omnigent-host owner without alias" (
            lib.all (o: i.schema.ownerAliases ? ${o}) owners
            && builtins.elem "transform/omnigent-alias" pipelines."metrics/host".processors
          ))
          (check "R3.1: an alias carries an owner name" (
            lib.all (alias: lib.all (o: !(lib.hasInfix o alias)) owners) (
              builtins.attrValues i.schema.ownerAliases
            )
          ))

          # Content: S1 stores metrics only (S7 adds logs behind ADR-008's stages).
          (check "R3.1: a logs or traces pipeline" (
            lib.all (lib.hasPrefix "metrics/") (builtins.attrNames pipelines)
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
          (check "R3.1: fleet queue below 24 h" (
            (e."otlp_http/fleet".sending_queue.queue_size or 0) >= 24 * 60 * fleetBytesPerMinute
          ))
          (check "R3.1: queues at or above 512 MiB" (lib.foldl' builtins.add 0 queueSizes < mib 512))

          # Envelope: the limiter refuses data before the unit's ceiling kills
          # the collector and its in-memory batches.
          (check "R3.1: memory_limiter at or above the collector's MemoryMax" (
            collectorMemoryMax != null
            && mib (p.memory_limiter.limit_mib or 0) < mib (lib.toInt (builtins.head collectorMemoryMax))
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
          (check "R3.1: a greptimedb*, zfs-set-*, zfs-assert-* or collector unit is not notified" (
            lib.all (name: builtins.elem name i.notifyUnits) (builtins.filter notifiedByPolicy hostUnits)
          ))
          # The wiring defines a unit for every listed name, so a misspelt
          # name would otherwise become a unit with nothing to run.
          (check "R3.1: a notified name is not a unit with an ExecStart" (
            lib.all (name: (i.services.${name}.serviceConfig or { }) ? ExecStart) i.notifyUnits
          ))
          (check "R3.1: a named unit is not wired to the notifier" (lib.all unitWired i.notifyUnits))
          (check "R3.1: a notified unit lacks the start-time RESOLVED hook sharing its stop hook's script" (
            lib.all startResolves i.notifyUnits
          ))
          (check
            "R3.1: notifier is not the rehearsed observability-notify-failed script with a 900 s interval"
            (notifier == "${deployedNotify.failed} %i" && i.notifierInterval == "900")
          )

          # Startup (host-metrics-collection "The collector starts after the databases exist").
          (check "R3.1: collector not ordered after the schema job" (
            builtins.elem "greptimedb-schema.service" i.services.opentelemetry-collector.after
            && builtins.elem "greptimedb-schema.service" i.services.opentelemetry-collector.wants
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
        systemdUnitsOverCap =
          i:
          onSettings {
            receivers.systemd.units =
              i.settings.receivers.systemd.units ++ map (n: "cap-${toString n}.service") (lib.range 1 20);
          } i;
        processFloorUnwired =
          i:
          onSettings {
            service.pipelines."metrics/process".processors =
              lib.remove "filter/process-min"
                i.settings.service.pipelines."metrics/process".processors;
          } i;
        limiterOverMemoryMax = onSettings { processors.memory_limiter.limit_mib = 600; };
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
        startHookDropped =
          i:
          i
          // {
            services = i.services // {
              opentelemetry-collector = lib.recursiveUpdate i.services.opentelemetry-collector {
                serviceConfig.ExecStartPost = builtins.filter (
                  hook: builtins.match (resolvedHook "start") hook == null
                ) (lib.toList (i.services.opentelemetry-collector.serviceConfig.ExecStartPost or [ ]));
              };
            };
          };
        # A oneshot whose start hook is another script could post RESOLVED twice.
        oneshotStartHookOtherScript =
          i:
          i
          // {
            services = i.services // {
              greptimedb-schema = lib.recursiveUpdate i.services.greptimedb-schema {
                serviceConfig.ExecStartPost = [
                  "-+/nix/store/${lib.fixedWidthString 32 "0" ""}-observability-notify-resolved start %n"
                ];
              };
            };
          };
        # A new disk unit that is not listed.
        unlistedDiskUnit =
          i:
          i
          // {
            services = i.services // {
              zfs-set-root-foo-quota = {
                unitConfig = { };
                serviceConfig.ExecStart = "/run/current-system/sw/bin/zfs set quota=1G zroot/root/foo";
              };
            };
          };
        # A listed name with no such service: the agent's wiring then creates
        # a unit carrying only the hooks.
        listedWithoutService =
          i:
          i
          // {
            notifyUnits = i.notifyUnits ++ [ "zfs-set-root-typo-quota" ];
            services = i.services // {
              zfs-set-root-typo-quota = {
                inherit (i.services.zfs-set-root-nix-quota) unitConfig;
                serviceConfig = builtins.removeAttrs i.services.zfs-set-root-nix-quota.serviceConfig [
                  "ExecStart"
                ];
              };
            };
          };
        schemaOrderDropped =
          i:
          i
          // {
            services = i.services // {
              opentelemetry-collector = i.services.opentelemetry-collector // {
                after = lib.remove "greptimedb-schema.service" i.services.opentelemetry-collector.after;
              };
            };
          };
        # R1.2's mutant.
        conversionRemoved = onSettings { processors."transform/exphist".metric_statements = [ ]; };
      };
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        otel-collector-config =
          assert lib.assertMsg (actual == [ ]) "otel-collector-config failures: ${builtins.toJSON actual}";
          assert lib.assertMsg (lib.all (mutant: failures (mutant input) != [ ]) (lib.attrValues mutants))
            "otel-collector-config accepted a mutant: ${
              builtins.toJSON (builtins.attrNames (lib.filterAttrs (_: m: failures (m input) == [ ]) mutants))
            }";
          pkgs.runCommand "otel-collector-config" { passthru = { inherit failures; }; } ''
            # The notifier's rate limit (review F1).
            test -e ${notifierRehearsal}
            touch "$out"
          '';
      };
    };
}
