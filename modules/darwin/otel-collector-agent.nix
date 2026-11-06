# The darwin collection fragment (ADR-003 items 1, 21-24; design D2-D4, D8),
# imported by the otel-collector agent role's darwinModule where the host's
# collect is true; the role declares the _otelcol account and the secrets.
# Relations within the host are assertions, which stibnite's activation
# evaluates before it switches. The rendered configurations are options so
# an extendModules override can change a value an assertion judges.
{ config, ... }:
let
  flakeLib = config.flake.lib;
  schema = flakeLib.otelCollectorSchema;
in
{
  flake.modules.darwin.otel-collector-agent =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.vanixiets.otelCollector.darwin;
      gens = config.clan.core.vars.generators;
      mib = n: n * 1024 * 1024;
      # The daemons this fragment declares; the calendar assertion covers
      # these only, because harmonia-gc and nix-cleanup-gcroots keep their
      # calendars (design D8).
      own = [
        "otelcol"
        "otelcol-process"
        "otel-host-probe"
        "prometheus-node-exporter"
        "otel-envelope"
      ];
      q = n: cfg.agentSettings.exporters.${n}.sending_queue or { };
      agentExporters = [
        "otlp_http/ingress"
        "otlp_http/ingress-logs"
      ];
      isLoopback =
        s:
        builtins.match "(https?://)?(127\\.[0-9]+\\.[0-9]+\\.[0-9]+|\\[::1]|localhost)(:[0-9]+)?(/.*)?" s
        != null;
      owners = lib.concatMap (
        n:
        let
          m = builtins.match "omnigent-host-(.+)" n;
        in
        lib.optional (m != null) (builtins.head m)
      ) (builtins.attrNames config.launchd.daemons);
      keptAlive = flakeLib.otelHostProbeLabels {
        inherit (schema) launchdLabels;
        daemonLabels = lib.mapAttrsToList (_: d: d.serviceConfig.Label) (
          lib.filterAttrs (_: d: (d.serviceConfig.KeepAlive or null) == true) config.launchd.daemons
        );
      };
      # The host's long-running org.nixos.* daemons, KeepAlive true or a
      # condition set; periodic jobs run a shell, find or jq whose names
      # would keep the operator's own (design D3).
      longRunning = lib.mapAttrsToList (_: d: d.serviceConfig.Label) (
        lib.filterAttrs (
          _: d:
          lib.hasPrefix "org.nixos." d.serviceConfig.Label
          && (
            d.serviceConfig.KeepAlive or null == true || builtins.isAttrs (d.serviceConfig.KeepAlive or null)
          )
        ) config.launchd.daemons
      );
      fleetGlobsMatching =
        label:
        builtins.filter (
          g:
          flakeLib.otelHostProbeLabels {
            launchdLabels = [ g ];
            daemonLabels = [ label ];
          } != [ ]
        ) (builtins.attrNames schema.process.darwinFleetExecutables);
      daemonLabels = lib.mapAttrsToList (_: d: d.serviceConfig.Label) config.launchd.daemons;
      fleetExecutables = lib.unique (
        lib.concatMap (
          label: map (g: schema.process.darwinFleetExecutables.${g}) (fleetGlobsMatching label)
        ) daemonLabels
      );
      omnigentPython =
        if owners == [ ] then null else config.services.omnigent-host.package.python.executable;
      rendered = flakeLib.otelCollectorDarwin {
        hostName = config.networking.hostName;
        certFile = gens.otel-cert.files."cert.pem".path;
        keyFile = gens.otel-cert.files."key.pem".path;
        caFile = pkgs.writeText "otel-ca.crt" gens.otel-ca.files."ca.crt".value;
        inherit fleetExecutables;
      };
    in
    {
      options.vanixiets.otelCollector.darwin = {
        agentSettings = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          description = "The agent's rendered configuration, flake.lib.otelCollectorDarwin's `agent`.";
        };
        processSettings = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          description = "otelcol-process's rendered configuration, flake.lib.otelCollectorDarwin's `process`.";
        };
      };

      config = {
        vanixiets.otelCollector.darwin = {
          agentSettings = rendered.agent;
          processSettings = rendered.process;
        };

        # Ordered as omnigent-host's: after users are created, before launchd
        # loads the jobs. /run is emptied at boot on darwin, so state lives
        # under /var (design D2).
        system.activationScripts.launchd.text = lib.mkBefore ''
          install -d -m 0700 -o _otelcol -g _otelcol /var/lib/opentelemetry-collector /var/lib/opentelemetry-collector/queue /var/lib/otel-envelope /var/log/otelcol
          install -d -m 0755 -o _prometheus-node-exporter -g _prometheus-node-exporter /var/lib/prometheus-node-exporter/textfile
        '';

        services.prometheus.exporters.node = {
          enable = true;
          inherit (rendered.node) listenAddress port extraFlags;
        };

        # Each job logs where its own account can open the file, because
        # launchd opens StandardOutPath and StandardErrorPath as the job's
        # UserName: /var/log/otelcol is _otelcol's, and the probe logs into
        # the home of _prometheus-node-exporter beside node_exporter's log.
        # `script` and `command` run behind /bin/wait4path /nix/store.
        launchd.daemons = {
          # The key's wait covers boot, before sops-install-secrets has run;
          # the certificate's hash changes the plist on a reissue, so
          # nix-darwin reloads the job (design D2, D5).
          otelcol = {
            script = ''
              /bin/wait4path ${gens.otel-cert.files."key.pem".path}
              exec ${lib.getExe' pkgs.opentelemetry-collector-contrib "otelcol-contrib"} --config ${
                (pkgs.formats.yaml { }).generate "otelcol-agent.yaml" cfg.agentSettings
              }
            '';
            environment.OTEL_CERT_SHA256 = builtins.hashString "sha256" gens.otel-cert.files."cert.pem".value;
            serviceConfig = {
              UserName = "_otelcol";
              GroupName = "_otelcol";
              KeepAlive = true;
              RunAtLoad = true;
              StandardOutPath = "/var/log/otelcol/otelcol.log";
              StandardErrorPath = "/var/log/otelcol/otelcol.log";
            };
          };
          # Root, for proc_pidinfo over other users' processes; no listener
          # and no credential (design D3; ADR-008 item 4).
          otelcol-process = {
            script = "exec ${lib.getExe' pkgs.opentelemetry-collector-contrib "otelcol-contrib"} --config ${
              (pkgs.formats.yaml { }).generate "otelcol-process.yaml" cfg.processSettings
            }";
            serviceConfig = {
              KeepAlive = true;
              RunAtLoad = true;
              StandardOutPath = "/var/log/otelcol/otelcol-process.log";
              StandardErrorPath = "/var/log/otelcol/otelcol-process.log";
            };
          };
          otel-host-probe = {
            script = "exec ${
              lib.getExe (
                flakeLib.otelHostProbe pkgs {
                  # ADR-004:121: the allow-listed labels this host defines,
                  # selected by the function the check judges.
                  labels = flakeLib.otelHostProbeLabels {
                    inherit (schema) launchdLabels;
                    daemonLabels = lib.mapAttrsToList (_: d: d.serviceConfig.Label) config.launchd.daemons;
                  };
                  devices = flakeLib.observabilityHosts.${config.networking.hostName}.smartDevices;
                  inherit (schema) ownerAliases;
                  textfileDir = "/var/lib/prometheus-node-exporter/textfile";
                }
              )
            }";
            serviceConfig = {
              UserName = "_prometheus-node-exporter";
              GroupName = "_prometheus-node-exporter";
              StartInterval = 60;
              RunAtLoad = true;
              StandardOutPath = "/var/lib/prometheus-node-exporter/otel-host-probe.log";
              StandardErrorPath = "/var/lib/prometheus-node-exporter/otel-host-probe.log";
            };
          };
          # R3.2 on the host (design D6): every 300 s, which skips sleep and
          # needs no zone (design D8), under the wrapper that posts its own
          # FAILED and RESOLVED to fleet-alerts, because a broken export path
          # would also stop a notice sent through the store. The token
          # reaches ntfy-send only as the path the wrapper sets for its calls.
          otel-envelope = {
            command = lib.concatStringsSep " " [
              (lib.getExe (
                flakeLib.observabilityNotifyRun pkgs {
                  label = "otel-envelope";
                  host = config.networking.hostName;
                  tokenFile = gens.ntfy-alerter.files.token.path;
                  stateDir = "/var/lib/otel-envelope";
                  logFile = "/var/lib/otel-envelope/notify.log";
                }
              ))
              "--"
              (lib.getExe (
                flakeLib.otelEnvelope pkgs {
                  hostName = config.networking.hostName;
                  inherit (rendered) targets exporters;
                  darwinMemory = {
                    launchctl = "/bin/launchctl";
                    top = "/usr/bin/top";
                    # The NixOS MemoryMax analogues (ADR-003 envelope).
                    limits = {
                      "org.nixos.otelcol" = 268435456;
                      "org.nixos.otelcol-process" = 134217728;
                    };
                  };
                }
              ))
            ];
            environment.STATE_DIRECTORY = "/var/lib/otel-envelope";
            serviceConfig = {
              UserName = "_otelcol";
              GroupName = "_otelcol";
              StartInterval = 300;
              StandardOutPath = "/var/log/otelcol/otel-envelope.log";
              StandardErrorPath = "/var/log/otelcol/otel-envelope.log";
            };
          };
        };

        # Value sources: the rendered ingress queues against SC's
        # fleetBytesPerMinute and ADR-003's 512 MiB envelope; each listener
        # against the loopback pattern; the fragment's daemons'
        # StartCalendarInterval against null; the host's omnigent-host-<owner>
        # daemons against SC's ownerAliases; SC's launchdKeptAlive against the
        # allow-listed labels of the host's daemons whose KeepAlive is true.
        assertions = [
          {
            assertion =
              lib.all (
                n:
                (q n).storage or null == "file_storage"
                && (q n).sizer or null == "bytes"
                && (cfg.agentSettings.exporters.${n}.retry_on_failure.max_elapsed_time or null) == "0s"
              ) agentExporters
              && ((q "otlp_http/ingress").queue_size or 0) >= 24 * 60 * schema.fleetBytesPerMinute;
            message = "otel-collector darwin agent: both ingress exporters must queue in file_storage by bytes with unlimited retry, and the metrics queue must hold 24 h at fleetBytesPerMinute (ADR-003 envelope; design D2).";
          }
          {
            assertion = lib.foldl' (s: n: s + ((q n).queue_size or 0)) 0 agentExporters < mib 512;
            message = "otel-collector darwin agent: the ingress exporters' queues must sum below 512 MiB (ADR-003 envelope).";
          }
          {
            assertion = lib.all isLoopback (
              [
                cfg.agentSettings.receivers.otlp.protocols.http.endpoint
                config.services.prometheus.exporters.node.listenAddress
                cfg.processSettings.exporters."otlp_http/agent".endpoint
              ]
              ++ map (r: r.pull.exporter.prometheus.host) cfg.agentSettings.service.telemetry.metrics.readers
            );
            message = "otel-collector darwin agent: every receiver, telemetry and node_exporter listener and otelcol-process's exporter must be on loopback (ADR-003 items 18-23).";
          }
          {
            assertion = lib.all (
              n: (config.launchd.daemons.${n}.serviceConfig.StartCalendarInterval or null) == null
            ) (builtins.filter (n: config.launchd.daemons ? ${n}) own);
            message = "otel-collector darwin agent: ${builtins.toJSON own} must use KeepAlive or StartInterval, never StartCalendarInterval, whose local-time firings coalesce at wake (design D8).";
          }
          {
            assertion =
              lib.all (o: schema.ownerAliases ? ${o}) owners
              && lib.all (a: lib.all (o: !(lib.hasInfix o a)) owners) (builtins.attrValues schema.ownerAliases);
            message = "otel-collector darwin agent: every omnigent-host-<owner> launchd daemon needs an alias in ownerAliases that does not contain an owner's name; owners ${builtins.toJSON owners}";
          }
          {
            assertion = lib.sort lib.lessThan schema.launchdKeptAlive == lib.sort lib.lessThan keptAlive;
            message = "otel-collector darwin agent: SC's launchdKeptAlive ${builtins.toJSON schema.launchdKeptAlive} must equal the allow-listed labels whose evaluated KeepAlive is true, ${builtins.toJSON keptAlive}, which LaunchdJobNotRunning expects running (ADR-004:123; design D9).";
          }
          {
            assertion =
              lib.all (l: builtins.length (fleetGlobsMatching l) == 1) longRunning
              && (
                omnigentPython == null
                || schema.process.darwinFleetExecutables."org.nixos.omnigent-host-*" == omnigentPython
              );
            message = "otel-collector darwin agent: each long-running org.nixos.* daemon ${builtins.toJSON longRunning} must match exactly one glob of SC's process.darwinFleetExecutables, and its omnigent-host-* name must be the omnigent package's interpreter ${builtins.toJSON omnigentPython}, so that otelcol-process keeps the fleet's own executables below the darwin floor (design D3; A77).";
          }
        ];
      };
    };
}
