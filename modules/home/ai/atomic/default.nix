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
# settings.json is merged rather than installed. atomic writes its own keys into
# that file — onboardedVersion, the changelog marker, the provider and model
# selection — and an install(1) of a nix-generated file would drop them, which
# for onboardedVersion means re-running the first-run wizard on every
# activation. The merge writes only the keys declared below, which come from
# modules/home/ai/agent-settings.nix so that pi's settings.json and this one
# cannot drift apart. auth.json and models-store.json are runtime state and are
# not managed here.
#
# packages is the one key the two agents do not share verbatim: atomic takes
# packagesForAtomic, which carries the extension exclusions that agent-settings
# declares for it. The key is still written rather than dropped, because
# merge-settings.sh can update a nix-owned key but not retract one.
#
# extensions is atomic's alone. It carries the force-excludes that keep pi-only
# extensions out of atomic, which is not a redundancy with packagesForAtomic:
# atomic inherits ~/.pi/agent as a config root unconditionally, so a file pi
# writes into its own extensions/ directory is loaded by atomic without either
# settings file naming it, and only this key can refuse it. See
# aiAgentSettings.piOnlyExtensions for the mechanism.
{ ... }:
let
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
      mergeSettings = pkgs.writeShellApplication {
        name = "atomic-merge-settings";
        runtimeInputs = [ pkgs.jq ];
        text = builtins.readFile ./merge-settings.sh;
      };
    in
    {
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
          description = "Nix-owned subset of atomic's settings.json. Each declared key is overwritten on activation; every key atomic writes and nix does not declare survives untouched.";
        };
      };

      config = {
        programs.atomic = {
          enable = lib.mkDefault true;

          settings = {
            inherit (config.aiAgentSettings) theme enableInstallTelemetry hideThinkingBlock;
            packages = config.aiAgentSettings.packagesForAtomic;
            extensions = config.aiAgentSettings.extensionsForAtomic;

            # Three model roles. The session default covers chat, planning, and
            # every workflow stage that pins no model. Implementation runs on
            # Astra because the builtin goal and ralph orchestrators pin it and
            # `worker` is the implementation writer those orchestrators hand off
            # to; the read-only codebase-* agents take Opus for quick research.
            # atomic rewrites the default* keys on /model and /thinking, so an
            # interactive switch survives only until the next activation.
            defaultProvider = "anthropic";
            defaultModel = "claude-fable-5-1";
            defaultThinkingLevel = "medium";
            modelThinkingLevels = {
              "anthropic/claude-fable-5-1" = "medium";
              "anthropic/claude-opus-5" = "medium";
              "openai-codex/gpt-6-astra" = "high";
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

        home.activation.atomicMergeSettings = lib.mkIf cfg.enable (
          let
            settingsFile = jsonFormat.generate "atomic-settings.json" cfg.settings;
          in
          lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            $DRY_RUN_CMD ${lib.getExe mergeSettings} ${settingsFile} ${cfg.configDir}/settings.json
          ''
        );
      };
    };
in
{
  flake.modules.homeManager.ai = content;
  flake.modules.homeManager.atomic = content;
}
