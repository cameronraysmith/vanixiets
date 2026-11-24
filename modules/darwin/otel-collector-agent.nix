# The darwin collection fragment (ADR-003 items 1, 21-24; design D2-D4, D8),
# imported by the otel-collector agent role's darwinModule where the host's
# collect is true; the role declares the _otelcol account and the secrets.
# Relations within the host are assertions, which stibnite's activation
# evaluates before it switches. The rendered configurations are options so
# an extendModules override can change a value an assertion judges.
# Where the host's row sets agentTelemetry, it also runs the agent-session
# collector, flake.lib.agentSessionCollector's settings for this host, as
# the launchd daemon org.nixos.otel-agent-session under _otelagent, which
# the role declares, beside its own envelope job
# (darwin-agent-session-telemetry design D2-D5).
{ config, self, ... }:
let
  flakeLib = config.flake.lib;
  schema = flakeLib.otelCollectorSchema;
  agentSessionLabel = "otel-agent-session";
  agentSessionStateDir = "/var/lib/otel-agent-session";
  agentSessionLogDir = "/var/log/otel-agent-session";
  agentSessionEnvelopeStateDir = "/var/lib/otel-agent-session-envelope";
  agentSessionTelemetryPort = 8890;
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
      row = flakeLib.observabilityHosts.${config.networking.hostName};
      # Static data from the host table, as the role's darwinModule reads it.
      agentTelemetry = row.agentTelemetry;
      langfuse = agentTelemetry && row.langfuse;
      caFile = pkgs.writeText "otel-ca.crt" gens.otel-ca.files."ca.crt".value;
      keyPath = gens.otel-cert.files."key.pem".path;
      langfuseFiles = {
        publicKeyFile = gens.langfuse.files.public-key.path;
        secretKeyFile = gens.langfuse.files.secret-key.path;
      };
      # The same function the NixOS hosts run, with the sops paths of the
      # client key and the Langfuse keys, which the daemon reads as their
      # owner or group, and the row's span queue (design D1, D5, D7).
      agentSession = flakeLib.agentSessionCollector {
        hostName = config.networking.hostName;
        inherit caFile;
        certFile = gens.otel-cert.files."cert.pem".path;
        keyFile = keyPath;
        queueDirectory = "${agentSessionStateDir}/queue";
        spanQueueMiB = row.agentSpanQueueMiB;
        telemetryPort = agentSessionTelemetryPort;
        langfuse = if langfuse then langfuseFiles else null;
      };
      agentSessionSettings = config.vanixiets.otelCollector.agentSessionSettings;
      agentSessionDaemon = config.launchd.daemons.${agentSessionLabel}.serviceConfig;
      agentSessionGoMemLimit = builtins.match "([0-9]+)MiB" (
        (lib.defaultTo { } agentSessionDaemon.EnvironmentVariables).GOMEMLIMIT or ""
      );
      # The daemons this fragment declares; the calendar assertion covers
      # these only, because harmonia-gc and nix-cleanup-gcroots keep their
      # calendars (design D8).
      own = [
        "otelcol"
        "otelcol-process"
        "otel-host-probe"
        "prometheus-node-exporter"
        "otel-envelope"
        agentSessionLabel
        "${agentSessionLabel}-envelope"
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
        inherit caFile;
        inherit fleetExecutables;
      };
      # launchd can start a collector at boot before sops-install-secrets has
      # written the files its settings name; its script polls, bounded, for
      # them (flake.lib.launchdSecretPoll, which says why not wait4path), and
      # an assertion requires the poll for every /run path in its settings.
      secretPoll =
        settings:
        flakeLib.launchdSecretPoll.prefix { } (
          flakeLib.launchdSecretPoll.namedIn config (builtins.toJSON settings)
        );
      secretPollAssertions =
        name: settings:
        let
          job = config.launchd.daemons.${name};
        in
        map
          (message: {
            assertion = false;
            inherit message;
          })
          (
            flakeLib.launchdSecretPoll.failures {
              label = "launchd.daemons.${name}";
              start = job.script;
              outer = job.serviceConfig.ProgramArguments;
              named = lib.unique (
                map builtins.head (
                  builtins.filter builtins.isList (builtins.split "(/run/[^\"' }]+)" (builtins.toJSON settings))
                )
              );
            }
          );
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
        envelopeMemoryLimits = lib.mkOption {
          type = lib.types.attrsOf lib.types.ints.positive;
          internal = true;
          readOnly = true;
          description = "C5's physical-footprint limit in bytes per launchd label, the NixOS MemoryMax analogues (ADR-003 envelope), read by otel-envelope.";
        };
        agentSessionEnvelopeMemoryLimits = lib.mkOption {
          type = lib.types.attrsOf lib.types.ints.positive;
          internal = true;
          readOnly = true;
          description = "C5's physical-footprint limit in bytes for org.nixos.otel-agent-session, read by its own envelope job (darwin-agent-session-telemetry design D4).";
        };
      };
      # The names the NixOS agent role declares, so the agent-telemetry
      # home module reads one option on either platform.
      options.vanixiets.otelCollector.agentTelemetry = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether this host's agent sessions export to the agent-session collector's loopback receiver; read by the agent-telemetry home module to turn on its emitters.";
      };
      options.vanixiets.otelCollector.langfuse = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether this host's agent-session collector also sends its spans to Langfuse Cloud.";
      };
      options.vanixiets.otelCollector.agentSessionSettings = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
        description = "The agent-session daemon's settings, flake.lib.agentSessionCollector's, where the host's row sets agentTelemetry.";
      };

      config = lib.mkMerge [
        {
          vanixiets.otelCollector.darwin = {
            agentSettings = rendered.agent;
            processSettings = rendered.process;
            # C5's limits. otelcol-process's 128 MiB came from one footprint of
            # 102 MiB at its first start (2026-11-06, commit 585128280). On
            # stibnite on 2026-11-19, after 5.3 days up, `footprint` read
            # otelcol-process at 111 MB: 41 MB dirty __DATA_CONST (the contrib
            # binary's load-time cost, the same in otelcol), about 60 MB of Go
            # runtime memory (untagged VM_ALLOCATE, 56 MB of it compressed but
            # still counted) and 10 MB else, with a peak of 133.4 MiB (vmmap)
            # and one C5 failure at 131 MiB (2026-11-19T00:50Z). otelcol read
            # 133.5 MiB, peak 137.3 MiB, under its 256 MiB. The check takes
            # 44 MiB as the fixed floor that GOMEMLIMIT cannot reduce.
            envelopeMemoryLimits = {
              "org.nixos.otelcol" = 268435456;
              "org.nixos.otelcol-process" = 134217728;
            };
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
            # The key's poll covers boot, before sops-install-secrets has
            # run; the certificate's hash changes the plist on a reissue, so
            # nix-darwin reloads the job (design D2, D5).
            otelcol = {
              script = ''
                ${secretPoll cfg.agentSettings}
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
              # The memory_limiter checks only the heap; the Go runtime keeps
              # up to its GC goal beyond it, which the footprint counts. 64 MiB,
              # the limiter's own limit_mib, keeps C5's 128 MiB above the
              # 44 MiB floor plus this bound (memorylimiterprocessor README:74-77).
              environment.GOMEMLIMIT = "64MiB";
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
                      limits = cfg.envelopeMemoryLimits;
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
          # daemons against SC's ownerAliases; the host's own kept-alive list,
          # flake.lib.launchdKeptAlive, against the allow-listed labels of the
          # host's daemons whose KeepAlive is true.
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
              assertion =
                cfg.agentSettings.receivers.otlp.protocols.http.endpoint != "127.0.0.1:4318"
                && cfg.processSettings.exporters."otlp_http/agent".endpoint != "http://127.0.0.1:4318";
              message = "otel-collector darwin agent: the fleet collector's otlp receiver and otelcol-process's exporter must not use 127.0.0.1:4318, the agent-session receiver on every host, so an emitter can never feed fleet through metrics/host (darwin-agent-session-telemetry design D2).";
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
              assertion =
                lib.sort lib.lessThan (flakeLib.launchdKeptAlive config.networking.hostName)
                == lib.sort lib.lessThan keptAlive;
              message = "otel-collector darwin agent: ${config.networking.hostName}'s kept-alive labels ${builtins.toJSON (flakeLib.launchdKeptAlive config.networking.hostName)} (flake.lib.launchdKeptAlive) must equal the allow-listed labels whose evaluated KeepAlive is true, ${builtins.toJSON keptAlive}, which LaunchdJobNotRunning expects running (ADR-004:123; design D9; darwin-agent-session-telemetry design D6).";
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
          ]
          ++ secretPollAssertions "otelcol" cfg.agentSettings;
        }
        (lib.mkIf agentTelemetry {
          vanixiets.otelCollector.agentSessionSettings = agentSession.settings;
          # D4's footprint limit (orchestrator D32): the agent process's
          # anonymous-memory peak at 16 senders with no ceiling, 535 MiB, plus
          # the 44 MiB darwin floor, rounded up to a multiple of 64 MiB.
          vanixiets.otelCollector.darwin.agentSessionEnvelopeMemoryLimits."org.nixos.${agentSessionLabel}" =
            mib 640;

          system.activationScripts.launchd.text = lib.mkBefore ''
            install -d -m 0700 -o _otelagent -g _otelagent ${agentSessionStateDir} ${agentSessionStateDir}/queue ${agentSessionLogDir}
            install -d -m 0700 -o _otelcol -g _otelcol ${agentSessionEnvelopeStateDir}
          '';

          launchd.daemons = {
            # As otelcol, under its own account: the waits cover boot before
            # sops-install-secrets has run, and the certificate's and the
            # Langfuse var's hashes reload the job when either changes (the
            # encrypted file's hash, never the value). launchd enforces no
            # memory ceiling here, so the bounds are GOMEMLIMIT and the
            # settings' limiter, and the envelope's C5 notices growth
            # (design D3, D4, D5).
            ${agentSessionLabel} = {
              script = ''
                /bin/wait4path ${keyPath}
                ${lib.optionalString langfuse ''
                  /bin/wait4path ${langfuseFiles.publicKeyFile}
                  /bin/wait4path ${langfuseFiles.secretKeyFile}
                ''}exec ${lib.getExe' pkgs.opentelemetry-collector-contrib "otelcol-contrib"} --config ${
                  (pkgs.formats.yaml { }).generate "${agentSessionLabel}.yaml" agentSessionSettings
                }
              '';
              environment = {
                GOMEMLIMIT = "${toString agentSession.goMemLimitMib}MiB";
                OTEL_CERT_SHA256 = builtins.hashString "sha256" gens.otel-cert.files."cert.pem".value;
              }
              // lib.optionalAttrs langfuse {
                LANGFUSE_VAR_SHA256 = builtins.hashFile "sha256" "${self}/vars/shared/langfuse/secret-key/secret";
              };
              serviceConfig = {
                UserName = "_otelagent";
                GroupName = "_otelagent";
                # initgroups(3), so the job holds _otelcert for the client key.
                InitGroups = true;
                KeepAlive = true;
                RunAtLoad = true;
                # A bind of 127.0.0.1:4318 that loses the race with otelcol's
                # release at the switch is retried after 5 s (design D2).
                ThrottleInterval = 5;
                ProcessType = "Standard";
                StandardOutPath = "${agentSessionLogDir}/${agentSessionLabel}.log";
                StandardErrorPath = "${agentSessionLogDir}/${agentSessionLabel}.log";
              };
            };
            # R3.2 over the daemon's own telemetry, as otel-envelope over
            # otelcol's, with C5 for the daemon alone; Langfuse's failed sends
            # page no one (agent-session-telemetry design D16).
            "${agentSessionLabel}-envelope" = {
              command = lib.concatStringsSep " " [
                (lib.getExe (
                  flakeLib.observabilityNotifyRun pkgs {
                    label = "${agentSessionLabel}-envelope";
                    host = config.networking.hostName;
                    tokenFile = gens.ntfy-alerter.files.token.path;
                    stateDir = agentSessionEnvelopeStateDir;
                    logFile = "${agentSessionEnvelopeStateDir}/notify.log";
                  }
                ))
                "--"
                (lib.getExe (
                  flakeLib.otelEnvelope pkgs {
                    hostName = config.networking.hostName;
                    telemetryUrl = "http://127.0.0.1:${toString agentSessionTelemetryPort}/metrics";
                    targets = flakeLib.otelEnvelopeTargets agentSessionSettings.receivers;
                    exporters = builtins.attrNames agentSessionSettings.exporters;
                    sendFailedExempt = lib.optional langfuse "otlp_http/langfuse";
                    darwinMemory = {
                      launchctl = "/bin/launchctl";
                      top = "/usr/bin/top";
                      limits = cfg.agentSessionEnvelopeMemoryLimits;
                    };
                  }
                ))
              ];
              environment.STATE_DIRECTORY = agentSessionEnvelopeStateDir;
              serviceConfig = {
                UserName = "_otelcol";
                GroupName = "_otelcol";
                StartInterval = 300;
                StandardOutPath = "/var/log/otelcol/${agentSessionLabel}-envelope.log";
                StandardErrorPath = "/var/log/otelcol/${agentSessionLabel}-envelope.log";
              };
            };
          };

          # Value sources: the daemon's settings against schema.nix's rates and
          # ADR-003's envelope (flake.lib.agentSessionAssertions, as on NixOS,
          # with no ceiling); its listeners and exporters against the loopback
          # pattern and the two remote endpoints; its plist and the
          # generators' owners and modes against design D3 and D5; the row's
          # notified units against its envelope's label.
          assertions =
            flakeLib.agentSessionAssertions {
              hostName = config.networking.hostName;
              settings = agentSessionSettings;
              inherit langfuse;
              goMemLimitMib =
                if agentSessionGoMemLimit == null then null else lib.toInt (builtins.head agentSessionGoMemLimit);
            }
            ++ [
              {
                assertion =
                  agentSessionSettings.receivers."otlp/local".protocols.http.endpoint == "127.0.0.1:4318"
                  && lib.all isLoopback (
                    map (r: "${r.pull.exporter.prometheus.host}") agentSessionSettings.service.telemetry.metrics.readers
                  )
                  && lib.all (
                    e:
                    lib.elem e.endpoint [
                      "https://[${flakeLib.hosts.magnetite.zerotier.address}]:4318"
                      schema.agentSession.langfuse.endpoint
                    ]
                  ) (builtins.attrValues agentSessionSettings.exporters);
                message = "otel-collector darwin agent: ${agentSessionLabel}'s otlp/local must be 127.0.0.1:4318, its telemetry on loopback, and its exporters only the ingress over the mesh and Langfuse Cloud (ADR-003 items 3, 18-23; darwin-agent-session-telemetry design D2).";
              }
              {
                assertion =
                  agentSessionDaemon.UserName or null == "_otelagent"
                  && agentSessionDaemon.GroupName or null == "_otelagent"
                  && agentSessionDaemon.KeepAlive or null == true
                  &&
                    config.users.groups._otelcert.members or [ ] == [
                      "_otelcol"
                      "_otelagent"
                    ]
                  && (
                    let
                      k = gens.otel-cert.files."key.pem";
                    in
                    k.owner == "_otelcol" && k.group == "_otelcert" && k.mode == "0440"
                  )
                  && (
                    !langfuse
                    ||
                      lib.all
                        (
                          f:
                          let
                            v = gens.langfuse.files.${f};
                          in
                          v.owner == "_otelagent" && v.group == "_otelagent" && v.mode == "0400"
                        )
                        [
                          "public-key"
                          "secret-key"
                        ]
                  );
                message = "otel-collector darwin agent: ${agentSessionLabel} must run kept alive as _otelagent, the client key must be _otelcol:_otelcert 0440 with _otelcert holding _otelcol and _otelagent, and the Langfuse keys _otelagent:_otelagent 0400, so the fleet collector and its envelope cannot read them (darwin-agent-session-telemetry design D3, D5).";
              }
              {
                assertion = lib.elem "${agentSessionLabel}-envelope" row.notifiedUnits;
                message = "otel-collector darwin agent: ${config.networking.hostName}'s row must list ${agentSessionLabel}-envelope in notifiedUnits, so LaunchdJobFailed leaves its failures to its own notice (darwin-agent-session-telemetry design D3).";
              }
            ];
        })
      ];
    };
}
