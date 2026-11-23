# Holds the agent-session telemetry emitters (openspec agent-session-telemetry,
# design D2, D8, D9) to their stated gates, read from the rendered homes:
#
# - on pyrite, a host whose observabilityHosts row sets agentTelemetry, the
#   Claude Code settings file each home writes (its managedConfigs entry, so a
#   writable copy, for the human and both workers) carries exactly the
#   telemetry keys and values below, with user.name the person (a worker's
#   owner, not its Unix account), and ~/.omp/agent/.env is exactly the lines
#   below;
# - the claude-glm and claude-cerebras wrappers' settings carry no telemetry
#   name, so other model providers' sessions do not export;
# - on cinnabar (NixOS, no flag), stibnite (darwin) and the claude-sandbox
#   profile, no Claude settings carry a telemetry name and no omp .env line
#   starts with OTEL_.
#
# The expectations are written out here rather than read from the module, so
# a key added to or dropped from the module (OTEL_LOG_RAW_API_BODIES added, or
# OTEL_LOG_TOOL_CONTENT dropped, say) fails this check. Evaluation-time
# obligations: the asserts fire when this attribute is evaluated; the value
# is the rendered pyrite files as a file.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        agent-telemetry-emitters =
          let
            # design D2's gates and D15's traces with tool content.
            claudeExpected = person: {
              CLAUDE_CODE_ENABLE_TELEMETRY = "1";
              CLAUDE_CODE_ENHANCED_TELEMETRY_BETA = "1";
              OTEL_METRICS_EXPORTER = "otlp";
              OTEL_LOGS_EXPORTER = "otlp";
              OTEL_TRACES_EXPORTER = "otlp";
              OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf";
              OTEL_EXPORTER_OTLP_ENDPOINT = "http://127.0.0.1:4318";
              OTEL_LOG_USER_PROMPTS = "1";
              OTEL_LOG_ASSISTANT_RESPONSES = "1";
              OTEL_LOG_TOOL_DETAILS = "1";
              OTEL_LOG_TOOL_CONTENT = "1";
              OTEL_BSP_MAX_QUEUE_SIZE = "64";
              OTEL_METRICS_INCLUDE_ACCOUNT_UUID = "false";
              OTEL_RESOURCE_ATTRIBUTES = "user.name=${person}";
            };
            # The metrics lines (design D2), the traces lines (design D13)
            # and one span per request (darwin-agent-session-telemetry
            # design D13), in the file's sorted order.
            ompExpected = person: ''
              OTEL_BSP_MAX_EXPORT_BATCH_SIZE=1
              OTEL_BSP_MAX_QUEUE_SIZE=64
              OTEL_EXPORTER_OTLP_METRICS_ENDPOINT=http://127.0.0.1:4318/v1/metrics
              OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
              OTEL_EXPORTER_OTLP_TIMEOUT=5000
              OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://127.0.0.1:4318/v1/traces
              OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT=full
              OTEL_LOGS_EXPORTER=none
              OTEL_RESOURCE_ATTRIBUTES=user.name=${person}
            '';

            telemetryName =
              name:
              lib.hasPrefix "OTEL_" name
              || lib.elem name [
                "CLAUDE_CODE_ENABLE_TELEMETRY"
                "CLAUDE_CODE_ENHANCED_TELEMETRY_BETA"
                "ENABLE_BETA_TRACING_DETAILED"
                "BETA_TRACING_ENDPOINT"
              ];
            telemetryOf = env: lib.filterAttrs (name: _: telemetryName name) env;
            ompFile =
              home:
              let
                file = home.home.file.".omp/agent/.env" or { enable = false; };
              in
              if file.enable then file.text else null;
            ompTelemetryLines =
              text: lib.filter (lib.hasPrefix "OTEL_") (lib.splitString "\n" (if text == null then "" else text));

            pyrite = self.nixosConfigurations.pyrite.config.home-manager.users;
            # Home user name -> the person its sessions run for.
            withFlag = {
              cameron = "cameron";
              omnigent-cameron = "cameron";
              omnigent-janettesmith = "janettesmith";
            };
            withoutFlag = {
              "cinnabar cameron" = self.nixosConfigurations.cinnabar.config.home-manager.users.cameron;
              "stibnite crs58" = self.darwinConfigurations.stibnite.config.home-manager.users.crs58;
              "claude-sandbox" = self.homeConfigurations."claude-sandbox@x86_64-linux".config;
            };

            claudeWrong = lib.filterAttrs (
              user: person:
              telemetryOf (pyrite.${user}.managedConfigs.claude-code-settings.settings.env or { })
              != claudeExpected person
            ) withFlag;
            ompWrong = lib.filterAttrs (user: person: ompFile pyrite.${user} != ompExpected person) withFlag;
            wrappersLeaking =
              lib.filter (name: telemetryOf pyrite.cameron.managedConfigs.${name}.settings.env != { })
                [
                  "claude-glm-settings"
                  "claude-cerebras-settings"
                ];
            claudeLeaking = lib.attrNames (
              lib.filterAttrs (
                _: home: telemetryOf (home.programs.claude-code.settings.env or { }) != { }
              ) withoutFlag
            );
            ompLeaking = lib.attrNames (
              lib.filterAttrs (_: home: ompTelemetryLines (ompFile home) != [ ]) withoutFlag
            );
            show = attrs: lib.concatStringsSep ", " (lib.attrNames attrs);
          in
          assert lib.assertMsg (claudeWrong == { })
            "agent-telemetry: pyrite Claude settings env must carry exactly the D2 and D15 gates; wrong for ${show claudeWrong}: ${
              builtins.toJSON (
                lib.mapAttrs (
                  user: _: telemetryOf (pyrite.${user}.managedConfigs.claude-code-settings.settings.env or { })
                ) claudeWrong
              )
            }";
          assert lib.assertMsg (ompWrong == { })
            "agent-telemetry: pyrite ~/.omp/agent/.env must be exactly the D2 metrics and D13 traces lines; wrong for ${show ompWrong}: ${
              builtins.toJSON (lib.mapAttrs (user: _: ompFile pyrite.${user}) ompWrong)
            }";
          assert lib.assertMsg (wrappersLeaking == [ ])
            "agent-telemetry: the wrappers must not export; telemetry names in ${lib.concatStringsSep ", " wrappersLeaking}";
          assert lib.assertMsg (claudeLeaking == [ ])
            "agent-telemetry: no Claude telemetry name may be set without agentTelemetry; set for ${lib.concatStringsSep ", " claudeLeaking}";
          assert lib.assertMsg (ompLeaking == [ ])
            "agent-telemetry: no omp OTEL_ line may be written without agentTelemetry; written for ${lib.concatStringsSep ", " ompLeaking}";
          pkgs.writeText "agent-telemetry-emitters.json" (
            builtins.toJSON (
              lib.mapAttrs (user: _: {
                claude = telemetryOf pyrite.${user}.managedConfigs.claude-code-settings.settings.env;
                omp = ompFile pyrite.${user};
              }) withFlag
            )
          );
      };
    };
}
