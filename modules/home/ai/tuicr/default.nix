# tuicr, a code review TUI, as a member of the homeManager.ai aggregate.
#
# hunk imports its option set from flake.inputs.hunk.homeManagerModules.hunk;
# tuicr ships no upstream home-manager, nixos, or darwin module, so this file
# declares options.programs.tuicr itself.
#
# Self-enabling, matching hunk: every ai user gets it. Both the enable flag and
# each settings leaf are defined with lib.mkDefault so a machine or user module
# can disable the program or override one setting without a definition collision.
{ ... }:
{
  flake.modules.homeManager.ai =
    {
      config,
      pkgs,
      lib,
      flake,
      ...
    }:
    let
      cfg = config.programs.tuicr;
      tomlFormat = pkgs.formats.toml { };
    in
    {
      options.programs.tuicr = {
        enable = lib.mkEnableOption "tuicr, a code review TUI that exports reviews to GitHub, GitLab, or the clipboard";

        package = lib.mkOption {
          type = lib.types.package;
          default = flake.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.tuicr;
          defaultText = lib.literalExpression "inputs.llm-agents.packages.\${pkgs.stdenv.hostPlatform.system}.tuicr";
          description = ''
            The tuicr package to install. Sourced from the llm-agents input rather
            than {function}`lib.mkPackageOption`, which would resolve `pkgs.tuicr`:
            llm-agents tracks upstream tuicr releases more closely than nixpkgs.
          '';
        };

        settings = lib.mkOption {
          inherit (tomlFormat) type;
          default = { };
          example = lib.literalExpression ''{ diff_view = "side-by-side"; }'';
          description = ''
            Freeform contents of {file}`$XDG_CONFIG_HOME/tuicr/config.toml`, documented
            at <https://github.com/agavra/tuicr/blob/main/docs/CONFIG.md>.

            Keys tuicr does not recognise are dropped with a startup warning rather
            than an error, so a typo degrades silently instead of failing the run.
          '';
        };
      };

      config = {
        programs.tuicr = {
          enable = lib.mkDefault true;
          settings = {
            theme = lib.mkDefault "catppuccin-mocha";
            wrap = lib.mkDefault true;
            # The startup check is a crates.io round trip whose only effect is a
            # status-bar "vX available" badge, and the badge's only in-tool remedy
            # is `tuicr update`, which for a store path shells out to
            # `nix profile upgrade` against a profile home-manager does not manage
            # (src/update/install/installation.rs).
            no_update_check = lib.mkDefault true;
          };
        };

        home.packages = lib.mkIf cfg.enable [ cfg.package ];

        aiSkills.extraSkillDirs = lib.mkIf cfg.enable [ "${cfg.package.src}/skills" ];

        # tuicr only reads this path (src/config/mod.rs, one fs::read_to_string at
        # startup), so a store symlink suffices; no managedConfigs entry is needed.
        xdg.configFile."tuicr/config.toml" = lib.mkIf cfg.enable {
          source = tomlFormat.generate "tuicr-config.toml" cfg.settings;
        };
      };
    };
}
