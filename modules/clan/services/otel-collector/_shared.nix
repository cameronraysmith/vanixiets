# The otel-collector service's shared bindings, imported by agent.nix,
# ingress.nix and service.nix with the flake's config. import-tree skips
# `_`-prefixed paths, so this file is not a flake-parts module of its own.
{ config }:
let
  nixosModules = config.flake.modules.nixos;
  darwinModules = config.flake.modules.darwin;
  flakeLib = config.flake.lib;
  schema = config.flake.lib.otelCollectorSchema;

  stateDir = "/var/lib/opentelemetry-collector";
  credentialsDir = "/run/credentials/opentelemetry-collector.service";

  # The agent-session collector, a unit of its own on agent-telemetry hosts
  # (agent-session-telemetry design D14): its state, its credentials, its
  # own telemetry port, and on the ingress host the loopback receiver it
  # hands its output to over mTLS.
  agentSessionUnit = "otel-agent-session";
  agentSessionStateDir = "/var/lib/${agentSessionUnit}";
  agentSessionCredentials = "/run/credentials/${agentSessionUnit}.service";
  agentSessionTelemetryPort = 8890;
  loopbackHandoff = flakeLib.agentSessionHandoff.address;

  mib = n: n * 1024 * 1024;

  # Persistent queue per exporter: at least 24 h of fleet and, for the
  # ingress collector process alone, under 640 MiB in total (ADR-003
  # envelope as amended 2026-11-23; darwin-agent-session-telemetry design
  # D35), asserted by checks.x86_64-linux.otel-collector-config. fleet's 480
  # MiB holds 29.4 h at the measured fleetBytesPerMinute. devloop's 53 MiB is
  # split between its metrics and its six tables, ci_attribute holding about
  # a day of store outage on the busiest day (S2 design D4); eval_run's 4 MiB
  # holds months of nixbot's roughly 100 evaluation lines a day, and
  # runtime_test_result's 1 MiB years of pyrite's weekly run, one line of
  # about 400 B per runtime test (declare-test-size-classes design D11). agent's 62
  # MiB is split between its metrics and its session events, each holding
  # about 2 h of three agent-telemetry hosts' assumed output while the store
  # is down (agent-session-telemetry design D10; darwin-agent-session-
  # telemetry design D7).
  queueBytes = {
    fleet = mib 480;
    devloop = mib 4;
    agent = mib 16;
    agent_session_event = mib 46;
    # Agent spans (design D13, D15): flake.lib.agentSessionHandoff's
    # 12,582,912 B holds about 17 min of three agent-telemetry hosts at
    # agentSpanBytesPerMinute while the store is down; a full queue refuses
    # the hand-off as retryable, so each host's agent-session collector then
    # holds the rest in its own queue.
    agent_span = flakeLib.agentSessionHandoff.spanQueueBytes;
    devloop_ci_attribute = mib 32;
    devloop_ci_build = mib 4;
    devloop_batch_event = mib 4;
    devloop_deploy_record = mib 4;
    devloop_eval_run = mib 4;
    devloop_runtime_test_result = mib 1;
  };

  # Imported by both roles. `package` accepts a single definition, and the
  # shared key makes the module system load this module once on a machine
  # holding both roles. The agent pipelines and `metrics/ingress` start with
  # this limiter; the per-database pipelines behind the routing connector only
  # strip the routing attribute (ADR-003 item 8; envelope 384 MiB under
  # MemoryMax 512M).
  collectorCore = {
    key = "vanixiets#otel-collector-core";
    imports = [
      (
        { lib, pkgs, ... }:
        {
          options.vanixiets.otelCollector = {
            ingress = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = ''
                Whether this host runs the ingress, set by
                flake.modules.nixos.otel-collector-ingress: the agent's
                pipelines then end in the in-process `forward` connector
                instead of the mTLS exporters to magnetite's ZeroTier receiver.
              '';
            };
            caFile = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              description = ''
                The otel-ca certificate as a store path, which the agent's
                exporters and the ingress receiver trust; a new CA changes the
                configuration and so restarts the collector.
              '';
            };
            smartDevices = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = ''
                NVMe devices read by a loopback smartctl exporter that the
                agent scrapes; none when empty.
              '';
            };
            agentTelemetry = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = ''
                Whether this host runs the agent-session collector,
                otel-agent-session.service: the loopback receiver `otlp/local`
                on 127.0.0.1:4318 and the pipelines `metrics/agent-session`,
                `logs/agent-session` and `traces/agent-session`, in a unit of
                their own beside the host's collector (agent-session-telemetry
                design D3, D8, D14). Set by the clan agent role from the
                host's flake.lib.observabilityHosts row; the agent-telemetry
                home module configures the emitters only where it is true.
              '';
            };
            langfuse = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = ''
                Whether the agent-session collector also sends its agent
                spans to Langfuse Cloud (agent-session-telemetry design D16):
                the connector forward/langfuse fans traces/agent-session's
                output, after every allow-list, cut and mask, out to
                traces/langfuse, which exports to Langfuse over OTLP/HTTP with
                a short finite retry. Set by the clan agent role from the
                host's flake.lib.observabilityHosts row; requires
                agentTelemetry.
              '';
            };
            agentSessionSettings = lib.mkOption {
              type = (pkgs.formats.yaml { }).type;
              default = { };
              description = ''
                The agent-session collector's configuration, rendered by the
                agent fragment where agentTelemetry is true and empty
                elsewhere; otel-agent-session.service runs it, and the checks
                and the fleet-ingress test read it (design D14).
              '';
            };
            envelopeBudget = lib.mkOption {
              type = lib.types.nullOr (
                lib.types.submodule {
                  options = {
                    storeUrl = lib.mkOption { type = lib.types.str; };
                    notifiedUnits = lib.mkOption { type = lib.types.attrsOf (lib.types.listOf lib.types.str); };
                    databases = lib.mkOption { type = lib.types.attrsOf lib.types.str; };
                  };
                }
              );
              default = null;
              description = ''
                flake.lib.otelEnvelope's `budget`, set by the clan ingress
                role: otel-envelope then also judges the store's series and
                row budget hourly as the store's `regulator`, whose password
                it loads as the regulator-password credential (design D8).
              '';
            };
            devloopRecordFiles = lib.mkOption {
              type = lib.types.attrsOf (
                lib.types.submodule {
                  options = {
                    file = lib.mkOption {
                      type = lib.types.str;
                      description = "The JSON-lines file the host appends one record per line to.";
                    };
                    table = lib.mkOption {
                      type = lib.types.str;
                      description = "The devloop table, a key of otelCollectorSchema.devloop.tables, whose allow-listed columns each line carries.";
                    };
                  };
                }
              );
              default = { };
              description = ''
                The host's JSON-lines record files the agent role ships into
                devloop, each through file_log/<name> (S4 design D5;
                declare-test-size-classes design D11). The agent role lists
                the deploy record as `deploy-record`, the receiver id magnetite
                has used since S2; a host adds its own files beside it.
              '';
            };
          };

          config = {
            services.opentelemetry-collector = {
              enable = true;
              package = pkgs.opentelemetry-collector-contrib;
              settings.processors.memory_limiter = {
                check_interval = "1s";
                limit_mib = 384;
              };
              # Every exporter's persistent queue, and the file and journal
              # receivers' offsets.
              settings.extensions.file_storage = {
                directory = "${stateDir}/queue";
                create_directory = true;
              };
              settings.service.extensions = [ "file_storage" ];
            };
            # nixpkgs restarts the collector after 100 ms, so five quick start
            # failures would hit systemd's default start limit and leave it
            # failed for good.
            systemd.services.opentelemetry-collector = {
              startLimitIntervalSec = 0;
              serviceConfig.RestartSec = "5s";
            };
          };
        }
      )
    ];
  };
in
{
  inherit
    nixosModules
    darwinModules
    flakeLib
    schema
    credentialsDir
    agentSessionUnit
    agentSessionStateDir
    agentSessionCredentials
    agentSessionTelemetryPort
    loopbackHandoff
    mib
    queueBytes
    collectorCore
    ;
}
