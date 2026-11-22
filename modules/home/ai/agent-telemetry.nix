# Agent session telemetry emitters (openspec agent-session-telemetry, design
# D2, D8, D9): Claude Code and omp export to the host's loopback collector
# receiver, and only on a host whose collector has that receiver
# (osConfig.vanixiets.otelCollector.agentTelemetry, set from the host's
# flake.lib.observabilityHosts row). Elsewhere (darwin, hosts without the
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
{ ... }:
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
      enabled = osConfig != null && (osConfig.vanixiets.otelCollector.agentTelemetry or false);
      receiver = "http://127.0.0.1:4318";
      resourceAttributes = "user.name=${cfg.person}";

      # Prompts, responses and tool details on (operator's content decision);
      # OTEL_LOG_TOOL_CONTENT, OTEL_LOG_RAW_API_BODIES, traces and
      # OTEL_RESOURCE_INCLUDE_HOST stay unset. Metric temporality stays
      # Claude's default delta (design D2).
      claudeCodeEnv = {
        CLAUDE_CODE_ENABLE_TELEMETRY = "1";
        OTEL_METRICS_EXPORTER = "otlp";
        OTEL_LOGS_EXPORTER = "otlp";
        OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf";
        OTEL_EXPORTER_OTLP_ENDPOINT = receiver;
        OTEL_LOG_USER_PROMPTS = "1";
        OTEL_LOG_ASSISTANT_RESPONSES = "1";
        OTEL_LOG_TOOL_DETAILS = "1";
        OTEL_METRICS_INCLUDE_ACCOUNT_UUID = "false";
        OTEL_RESOURCE_ATTRIBUTES = resourceAttributes;
      };

      # omp exports a signal only when that signal has an endpoint, so with a
      # metrics endpoint alone it sends metrics and nothing else.
      ompMetricsEnv = {
        OTEL_EXPORTER_OTLP_METRICS_ENDPOINT = "${receiver}/v1/metrics";
        OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf";
        OTEL_LOGS_EXPORTER = "none";
        OTEL_RESOURCE_ATTRIBUTES = resourceAttributes;
      };
      # omp's traces settings (design D13): the traces endpoint, the content
      # level, OTEL_BSP_MAX_QUEUE_SIZE and OTEL_EXPORTER_OTLP_TIMEOUT are
      # added here, and only here, when the traces pipeline lands.
      ompTracesEnv = { };
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
        person = lib.mkOption {
          type = lib.types.strMatching "[a-z_][a-z0-9_-]*";
          default = config.home.username;
          defaultText = lib.literalExpression "config.home.username";
          description = ''
            The person a session runs for, stamped as the resource attribute
            `user.name`: the home's user for a human, the worker's owner for an
            Omnigent worker (design D4).
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
                if enabled then "of design D2" else "none (this host has no agentTelemetry)"
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
