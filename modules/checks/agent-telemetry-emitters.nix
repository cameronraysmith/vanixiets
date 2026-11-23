# Holds the agent-session telemetry emitters (openspec agent-session-telemetry,
# design D2, D8, D9) to their stated gates, read from the rendered homes:
#
# - on pyrite and stibnite, hosts whose observabilityHosts row sets
#   agentTelemetry, the Claude Code settings file each home writes (its
#   managedConfigs entry, so a writable copy, for the humans and pyrite's
#   workers) carries exactly the telemetry keys and values of
#   flake.lib.omnigentFleetObligations.telemetryFiles, with user.name the
#   person (a worker's owner, not its Unix account; stibnite's crs58 as
#   cameron, its flake.userAliases name, darwin-agent-session-telemetry
#   design D10), and ~/.omp/agent/.env is exactly its lines. A worker's home
#   alone adds vanixiets.harness_host=omnigent to the resource attributes, a
#   person's own home never (darwin-agent-session-telemetry design D15).
#   stibnite's worker home, a standalone generation, is held to the same
#   files by that obligation's workerTelemetry case in
#   checks.aarch64-darwin.darwin-stibnite;
# - the claude-glm and claude-cerebras wrappers' settings carry no telemetry
#   name, so other model providers' sessions do not export;
# - on cinnabar (NixOS, no flag), rosegold (darwin, no flag; argentum is the
#   same archetype, a laptop whose row sets neither flag, so one stands for
#   both) and the claude-sandbox profile, no Claude settings carry a
#   telemetry name and no omp .env line starts with OTEL_.
#
# A key added to or dropped from the module (OTEL_LOG_RAW_API_BODIES added,
# or OTEL_LOG_TOOL_CONTENT dropped, say), or a person stamped as the account
# name (crs58), fails this check. Evaluation-time obligations: the asserts
# fire when this attribute is evaluated; the value is the rendered files of
# the flagged homes as a file.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        agent-telemetry-emitters =
          let
            inherit (self.lib.omnigentFleetObligations.telemetryFiles)
              claudeExpected
              ompExpected
              telemetryOf
              ompFile
              claudeOf
              claudeProgramOf
              ompTelemetryLines
              ;

            pyrite = self.nixosConfigurations.pyrite.config.home-manager.users;
            stibnite = self.darwinConfigurations.stibnite.config;
            # Each flagged home, the person its sessions run for and whether
            # it is an Omnigent worker's.
            withFlag = {
              "pyrite cameron" = {
                home = pyrite.cameron;
                person = "cameron";
                worker = false;
              };
              "pyrite omnigent-cameron" = {
                home = pyrite.omnigent-cameron;
                person = "cameron";
                worker = true;
              };
              "pyrite omnigent-janettesmith" = {
                home = pyrite.omnigent-janettesmith;
                person = "janettesmith";
                worker = true;
              };
              "stibnite crs58" = {
                home = stibnite.home-manager.users.crs58;
                person = "cameron";
                worker = false;
              };
            };
            resourceOf =
              f: "user.name=${f.person}" + lib.optionalString f.worker ",vanixiets.harness_host=omnigent";
            withoutFlag = {
              "cinnabar cameron" = self.nixosConfigurations.cinnabar.config.home-manager.users.cameron;
              "rosegold cameron" = self.darwinConfigurations.rosegold.config.home-manager.users.cameron;
              "claude-sandbox" = self.homeConfigurations."claude-sandbox@x86_64-linux".config;
            };

            claudeWrong = lib.filterAttrs (_: f: claudeOf f.home != claudeExpected (resourceOf f)) withFlag;
            ompWrong = lib.filterAttrs (_: f: ompFile f.home != ompExpected (resourceOf f)) withFlag;
            wrappersLeaking =
              lib.concatMap
                (
                  label:
                  map (name: "${label} ${name}") (
                    lib.filter (name: telemetryOf withFlag.${label}.home.managedConfigs.${name}.settings.env != { }) [
                      "claude-glm-settings"
                      "claude-cerebras-settings"
                    ]
                  )
                )
                [
                  "pyrite cameron"
                  "stibnite crs58"
                ];
            claudeLeaking = lib.attrNames (lib.filterAttrs (_: home: claudeProgramOf home != { }) withoutFlag);
            ompLeaking = lib.attrNames (
              lib.filterAttrs (_: home: ompTelemetryLines (ompFile home) != [ ]) withoutFlag
            );
            show = attrs: lib.concatStringsSep ", " (lib.attrNames attrs);
          in
          assert lib.assertMsg (claudeWrong == { })
            "agent-telemetry: flagged homes' Claude settings env must carry exactly the D2 and D15 gates with their person and, for a worker's, its harness host; wrong for ${show claudeWrong}: ${
              builtins.toJSON (lib.mapAttrs (_: f: claudeOf f.home) claudeWrong)
            }";
          assert lib.assertMsg (ompWrong == { })
            "agent-telemetry: flagged homes' ~/.omp/agent/.env must be exactly the D2 metrics and D13 traces lines with their person and, for a worker's, its harness host; wrong for ${show ompWrong}: ${
              builtins.toJSON (lib.mapAttrs (_: f: ompFile f.home) ompWrong)
            }";
          assert lib.assertMsg (wrappersLeaking == [ ])
            "agent-telemetry: the wrappers must not export; telemetry names in ${lib.concatStringsSep ", " wrappersLeaking}";
          assert lib.assertMsg (claudeLeaking == [ ])
            "agent-telemetry: no Claude telemetry name may be set without agentTelemetry; set for ${lib.concatStringsSep ", " claudeLeaking}";
          assert lib.assertMsg (ompLeaking == [ ])
            "agent-telemetry: no omp OTEL_ line may be written without agentTelemetry; written for ${lib.concatStringsSep ", " ompLeaking}";
          pkgs.writeText "agent-telemetry-emitters.json" (
            builtins.toJSON (
              lib.mapAttrs (_: f: {
                claude = claudeOf f.home;
                omp = ompFile f.home;
              }) withFlag
            )
          );
      };
    };
}
