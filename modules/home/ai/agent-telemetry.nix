# Agent session telemetry emitters (openspec agent-session-telemetry, design
# D2, D8, D9): Claude Code and omp export to the host's loopback collector
# receiver, and only where `agentTelemetry.enable` is set: by default on a
# host whose collector has that receiver
# (osConfig.vanixiets.otelCollector.agentTelemetry, set from the host's
# flake.lib.observabilityHosts row, on NixOS and darwin alike), and on a
# darwin Omnigent worker, a standalone home, by its builder
# (darwin-agent-session-telemetry design D10). Elsewhere (hosts without the
# flag, standalone homes such as claude-sandbox) this module sets nothing.
#
# Imported by homeManager.ai (every human home) and homeManager.omnigent-worker
# (every worker home); the operator decided all users, with the group's
# consent recorded (A189).
#
# Claude Code reads the gates from user settings' `env`, which applies to every
# session and overrides the shell; project settings cannot set them
# (settings-reference.md:2441-2491, A190). omp reads ~/.omp/agent/.env itself
# before it builds its exporter, on every launch path including omnigent's ACP
# children, which omnigent strips OTEL_* from (A191, A195).
#
# The collector, not these gates, enforces what leaves the host (design D3):
# a key added here that the collector does not allow is dropped there.
{ config, ... }:
let
  # The person a human home's user name is (crs58 is cameron), from
  # modules/home/users/aliases.nix; an unknown name fails evaluation rather
  # than stamp a name the fleet does not know (design D10).
  inherit (config.flake.lib) personOf;
in
{
  flake.modules.homeManager.agent-telemetry =
    {
      config,
      lib,
      osConfig ? null,
      ...
    }:
    let
      cfg = config.agentTelemetry;
      enabled = cfg.enable;
      receiver = "http://127.0.0.1:4318";
      resourceAttributes = lib.concatStringsSep "," (
        [ "user.name=${cfg.person}" ]
        ++ lib.optional (cfg.harnessHost != null) "vanixiets.harness_host=${cfg.harnessHost}"
      );

      # Prompts, responses and tool details on (operator's content decision);
      # tool output on (design D15): Claude's beta traces with tool content,
      # since its tool output exists only as the `tool.output` span event.
      # Its span buffer holds at most 64 spans, as omp's does: tool spans
      # carry up to 60 KB each, and 2.1.330's batch span processor reads
      # OTEL_BSP_MAX_QUEUE_SIZE (default 2048) from the environment.
      # OTEL_LOG_RAW_API_BODIES (the whole conversation on every request),
      # detailed beta tracing and OTEL_RESOURCE_INCLUDE_HOST stay unset.
      # Metric temporality stays Claude's default delta (design D2).
      claudeCodeEnv = {
        CLAUDE_CODE_ENABLE_TELEMETRY = "1";
        CLAUDE_CODE_ENHANCED_TELEMETRY_BETA = "1";
        OTEL_METRICS_EXPORTER = "otlp";
        OTEL_LOGS_EXPORTER = "otlp";
        OTEL_TRACES_EXPORTER = "otlp";
        OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf";
        OTEL_EXPORTER_OTLP_ENDPOINT = receiver;
        OTEL_LOG_USER_PROMPTS = "1";
        OTEL_LOG_ASSISTANT_RESPONSES = "1";
        OTEL_LOG_TOOL_DETAILS = "1";
        OTEL_LOG_TOOL_CONTENT = "1";
        OTEL_BSP_MAX_QUEUE_SIZE = "64";
        OTEL_METRICS_INCLUDE_ACCOUNT_UUID = "false";
        OTEL_RESOURCE_ATTRIBUTES = resourceAttributes;
      };

      # omp exports a signal only when that signal has an endpoint, so with a
      # metrics endpoint and a traces endpoint it sends those and no logs.
      ompMetricsEnv = {
        OTEL_EXPORTER_OTLP_METRICS_ENDPOINT = "${receiver}/v1/metrics";
        OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf";
        OTEL_LOGS_EXPORTER = "none";
        OTEL_RESOURCE_ATTRIBUTES = resourceAttributes;
      };
      # omp's traces (design D13, D15): spans to the receiver with message
      # content at `full`, since omp puts content only on spans; the host's
      # traces/agent-session keeps the newest prompt, the output and the
      # tool results and drops the history. omp's span buffer holds at most
      # 64 spans (OTel's default 2048 of about 600 KB chat spans would be
      # about 1.2 GB while the collector is down), and an export gives up
      # after 5 s, its retries included (A196).
      ompTracesEnv = {
        OTEL_EXPORTER_OTLP_TRACES_ENDPOINT = "${receiver}/v1/traces";
        OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT = "full";
        OTEL_BSP_MAX_QUEUE_SIZE = "64";
        # One span per request: none can exceed the collector's 20 MiB body limit, which removed the OOM kills at 16 senders (darwin-agent-session-telemetry D13).
        OTEL_BSP_MAX_EXPORT_BATCH_SIZE = "1";
        OTEL_EXPORTER_OTLP_TIMEOUT = "5000";
      };
      ompEnv = ompMetricsEnv // ompTracesEnv;
      ompEnvText = lib.concatLines (lib.mapAttrsToList (name: value: "${name}=${value}") ompEnv);

      # Every name that turns on or shapes Claude Code's export, set here or not.
      telemetryName =
        name:
        lib.hasPrefix "OTEL_" name
        || lib.elem name [
          "CLAUDE_CODE_ENABLE_TELEMETRY"
          "CLAUDE_CODE_ENHANCED_TELEMETRY_BETA"
          "ENABLE_BETA_TRACING_DETAILED"
          "BETA_TRACING_ENDPOINT"
        ];
      renderedClaude = lib.filterAttrs (name: _: telemetryName name) (
        config.programs.claude-code.settings.env or { }
      );
      ompFile = config.home.file.".omp/agent/.env" or { enable = false; };
      renderedOmp = if ompFile.enable then ompFile.text else null;
      ompTelemetryLines = lib.filter (lib.hasPrefix "OTEL_") (
        lib.splitString "\n" (if renderedOmp == null then "" else renderedOmp)
      );
    in
    {
      key = "vanixiets/agent-telemetry";

      options.agentTelemetry = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = osConfig != null && (osConfig.vanixiets.otelCollector.agentTelemetry or false);
          defaultText = lib.literalExpression "osConfig != null && (osConfig.vanixiets.otelCollector.agentTelemetry or false)";
          description = ''
            Whether Claude Code and omp export to the loopback agent-session
            receiver. A standalone home, such as a darwin Omnigent worker's
            (osConfig = null), sets it from its host's row.
          '';
        };
        person = lib.mkOption {
          type = lib.types.strMatching "[a-z_][a-z0-9_-]*";
          default = personOf config.home.username;
          defaultText = lib.literalMD "the `flake.userAliases` key naming `home.username`, else `home.username` when it is a flake user or alias";
          description = ''
            The person a session runs for, stamped as the resource attribute
            `user.name`: the home's user, or its alias (crs58 is cameron), for a
            human, the worker's owner for an Omnigent worker (design D4).
          '';
        };
        harnessHost = lib.mkOption {
          type = lib.types.nullOr (lib.types.enum [ "omnigent" ]);
          default = null;
          description = ''
            The harness host whose worker home this is, stamped as the
            resource attribute `vanixiets.harness_host` beside `user.name`;
            null, and no attribute, in a person's own home
            (darwin-agent-session-telemetry design D15).
          '';
        };
        claudeCodeEnvNames = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          readOnly = true;
          default = lib.optionals enabled (lib.attrNames claudeCodeEnv);
          description = ''
            The settings `env` names this module adds for Claude Code, which
            the claude-glm and claude-cerebras wrappers remove so sessions on
            other model providers do not export.
          '';
        };
      };

      config = lib.mkMerge [
        (lib.mkIf enabled {
          programs.claude-code.settings.env = claudeCodeEnv;
          home.file.".omp/agent/.env".text = ompEnvText;
        })
        {
          assertions = [
            {
              assertion = renderedClaude == lib.optionalAttrs enabled claudeCodeEnv;
              message = "agent-telemetry: Claude Code settings env must carry exactly the emitter gates ${
                if enabled then "of design D2 and D15" else "none (this host has no agentTelemetry)"
              }; telemetry keys found: ${builtins.toJSON renderedClaude}";
            }
            {
              assertion = if enabled then renderedOmp == ompEnvText else ompTelemetryLines == [ ];
              message = "agent-telemetry: ~/.omp/agent/.env must ${
                if enabled then
                  "hold exactly ${builtins.toJSON ompEnvText}"
                else
                  "set no OTEL_ name (this host has no agentTelemetry)"
              }; found ${builtins.toJSON renderedOmp}";
            }
          ];
        }
      ];
    };
}
