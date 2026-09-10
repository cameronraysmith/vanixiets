# pi coding agent, as a member of the homeManager.ai aggregate.
#
# Global instructions arrive through the upstream `context` option, which writes
# AGENTS.md into configDir — the path pi already reads. programs.agents-md must
# therefore NOT gain a ~/.pi/agent/AGENTS.md destination of its own; two
# declarations of one target trip home-manager's duplicate-file assertion.
#
# No skills are declared here either. pi discovers ~/.agents/skills, which
# modules/home/ai/skills/default.nix populates; a second sink under
# ~/.pi/agent/skills would take precedence over it and shadow the real tree.
{ ... }:
let
  content =
    {
      pkgs,
      config,
      lib,
      flake,
      ...
    }:
    let
      cfg = config.programs.pi-coding-agent;
      jsonFormat = pkgs.formats.json { };
    in
    {
      options.programs.pi-coding-agent.mutableSettings = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Use a mutable copy instead of an immutable nix store symlink for settings.json. Allows pi to write to its settings at runtime at the cost of nix-declared state being overwritten between activations.";
      };

      config = {
        programs.pi-coding-agent = {
          enable = true;
          mutableSettings = true;
          package = flake.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.pi;

          context = config.programs.agents-md.settings.text;
          extraPackages = [
            pkgs.direnv
            pkgs.diffutils
            pkgs.git
            pkgs.jujutsu
            pkgs.rip2
          ];

          # https://pi.dev/docs/latest/settings
          #
          # These keys are declared in modules/home/ai/agent-settings.nix so
          # pi's file and atomic's are generated from one expression.
          #
          # `packages` is the exception: pi's value is the shared list plus
          # piOnlyPackages, which atomic never sees because its own `packages`
          # declaration shadows pi's rather than merging with it. See that
          # option's description for the mechanism and for why pi-vim is scoped
          # this way.
          settings = {
            inherit (config.aiAgentSettings)
              theme
              enableInstallTelemetry
              hideThinkingBlock
              ;
            packages = config.aiAgentSettings.packages ++ config.aiAgentSettings.piOnlyPackages;
          };
        };

        home.file = {
          # Mutable settings: suppress the upstream symlink-style home.file entry on
          # the ABSOLUTE key upstream actually writes to, "${cfg.configDir}/settings.json"
          # (home-manager modules/programs/pi-coding-agent.nix). A relative key is a
          # silent no-op that leaves the store symlink in place and only surfaces
          # later as a checkLinkTargets backup conflict. Mirrors
          # modules/home/ai/claude-code/default.nix.
          #
          # The copy is required because pi rewrites this file in place — /settings,
          # /model, /theme, and `pi install` all persist to it — and a read-only
          # store symlink makes those writes fail. Scoped to settings.json: pi has
          # no writer for keybindings.json or models.json.
          "${cfg.configDir}/settings.json".enable = lib.mkIf cfg.mutableSettings (lib.mkForce false);
          "${cfg.configDir}/extensions/edit-write-policy.ts".source = ./policy/edit-write-policy.ts;
          # Vendored byte-for-byte from aldoborrero/pi-agent-kit commit
          # 128c4c08396961ea8f934111ba1aad0b33c525b2, path
          # themes/catppuccin-mocha.json. The in-file $schema URL points at
          # badlogic/pi-mono, which owns the theme format rather than this
          # content, so it is not the provenance. JSON admits no comment, so
          # these coordinates are recorded here and in
          # openspec/specs/pi-agent-environment/spec.md; the content is pinned by
          # the sha256 literal in modules/checks/pi-agent-environment.nix, which
          # must be re-derived alongside any refresh of the copy.
          "${cfg.configDir}/themes/catppuccin-mocha.json".source = ./themes/catppuccin-mocha.json;
          # permission-gate resolves this path itself rather than through pi's
          # configDir: its configDir() honours a ~/.pi/agent/pi-agent-extensions.json
          # override, then $XDG_CONFIG_HOME, then ~/.config. Neither the override
          # file nor XDG_CONFIG_HOME is set anywhere under modules/home, so this
          # literal is the path the gate reads. Setting XDG_CONFIG_HOME would
          # strand this file silently and drop the gate to its built-in rules.
          ".config/pi-agent-extensions/permission-gate/rules.ts".source = ./policy/permission-rules.ts;
        };

        home.activation.piCodingAgentMutableSettings = lib.mkIf cfg.mutableSettings (
          let
            settingsFile = jsonFormat.generate "pi-coding-agent-settings.json" cfg.settings;
          in
          lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            $DRY_RUN_CMD install -Dm644 ${settingsFile} ${cfg.configDir}/settings.json
          ''
        );
      };
    };
in
{
  flake.modules.homeManager.ai = content;
  flake.modules.homeManager.pi = content;
}
