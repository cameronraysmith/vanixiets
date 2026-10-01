# atomic, a terminal coding agent, as a member of the homeManager.ai aggregate.
#
# atomic ships no upstream home-manager, nixos, or darwin module, so this file
# declares options.programs.atomic itself.
#
# The package is this repository's own pkgs/by-name/atomic rather than a flake
# input, so lib.mkPackageOption resolves it: modules/nixpkgs/compose.nix merges
# the perSystem packages set into flake.overlays.default, which
# modules/nixpkgs/base-defaults.nix wires into every machine's nixpkgs.overlays.
#
# settings.json is rendered by managedConfigs: every activation rewrites it from
# the keys declared below, keeping only atomic's onboarding and changelog
# markers from the existing file, so the first-run wizard does not reappear.
# The declared keys come from modules/home/ai/agent-settings.nix so that pi's
# settings.json and this one cannot drift apart. auth.json and
# models-store.json are runtime state and are not managed here.
#
# packages is the one key the two agents do not share verbatim: atomic takes
# packagesForAtomic, which carries the extension exclusions that agent-settings
# declares for it.
#
# extensions is atomic's alone. It carries the force-excludes that keep pi-only
# extensions out of atomic, which is not a redundancy with packagesForAtomic:
# atomic inherits ~/.pi/agent as a config root unconditionally, so a file pi
# writes into its own extensions/ directory is loaded by atomic without either
# settings file naming it, and only this key can refuse it. See
# aiAgentSettings.piOnlyExtensions for the mechanism.
{ config, ... }:
let
  managedConfigsModule = config.flake.modules.homeManager.managedConfigs;
  content =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      cfg = config.programs.atomic;
      jsonFormat = pkgs.formats.json { };
    in
    {
      imports = [ managedConfigsModule ];

      options.programs.atomic = {
        enable = lib.mkEnableOption "atomic, a terminal coding agent with read, bash, edit, and write tools and session management";

        package = lib.mkPackageOption pkgs "atomic" { };

        configDir = lib.mkOption {
          type = lib.types.str;
          default = "${config.home.homeDirectory}/.atomic/agent";
          description = "Directory atomic reads its configuration and runtime state from.";
        };

        settings = lib.mkOption {
          type = jsonFormat.type;
          default = { };
          description = "Content of atomic's settings.json, rewritten on every activation. firstRunOnboardingStartedVersion, lastChangelogVersion, and onboardedVersion are kept from the existing file; every other key atomic writes lasts until the next activation.";
        };
      };

      config = {
        programs.atomic = {
          enable = lib.mkDefault true;

          settings = {
            inherit (config.aiAgentSettings) theme enableInstallTelemetry hideThinkingBlock;
            enableAnalytics = false;
            packages = config.aiAgentSettings.packagesForAtomic;
            extensions = config.aiAgentSettings.extensionsForAtomic;

            # Three model roles. The session default covers chat, planning, and
            # every workflow stage that pins no model. Implementation runs on
            # Astra because the builtin goal and ralph orchestrators pin it and
            # `worker` is the implementation writer those orchestrators hand off
            # to; the read-only codebase-* agents take Opus for quick research.
            # atomic rewrites the default* keys on /model and /thinking, so an
            # interactive switch survives only until the next activation.
            defaultProvider = "openai-codex";
            defaultModel = "gpt-6-astra";
            defaultThinkingLevel = "medium";
            modelThinkingLevels = {
              "anthropic/claude-fable-5-1" = "medium";
              "anthropic/claude-opus-5" = "medium";
              "openai-codex/gpt-6-astra" = "medium";
            };
            fallbackModels = [
              "openai-codex/gpt-6-astra:high"
              "anthropic/claude-opus-5:medium"
            ];
            subagents.agentOverrides =
              let
                research = {
                  model = "anthropic/claude-opus-5:medium";
                };
              in
              {
                codebase-locator = research;
                codebase-analyzer = research;
                codebase-pattern-finder = research;
                codebase-online-researcher = research;
                codebase-research-locator = research;
                codebase-research-analyzer = research;
                worker = {
                  model = "openai-codex/gpt-6-astra:medium";
                };
              };
          };
        };

        home.packages = lib.mkIf cfg.enable [ cfg.package ];

        managedConfigs.atomic-settings = lib.mkIf cfg.enable {
          target = "${cfg.configDir}/settings.json";
          format = "json";
          settings = cfg.settings;
          appOwned = [
            "firstRunOnboardingStartedVersion"
            "lastChangelogVersion"
            "onboardedVersion"
          ];
        };
      };
    };
in
{
  flake.modules.homeManager.ai = content;
  flake.modules.homeManager.atomic = content;
}
