# tuicr, a code review TUI, as a member of the homeManager.ai aggregate.
#
# home-manager declares options.programs.tuicr (modules/programs/tuicr.nix):
# enable, package, settings, and themes, writing settings to
# $XDG_CONFIG_HOME/tuicr/config.toml. This file only sets values on that module.
#
# Self-enabling, matching hunk: every ai user gets it. The enable flag, the
# package, and each settings leaf are defined with lib.mkDefault so a machine or
# user module can disable the program or override one setting without a
# definition collision.
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
    in
    {
      programs.tuicr = {
        enable = lib.mkDefault true;
        # The upstream default is pkgs.tuicr; llm-agents tracks upstream tuicr
        # releases more closely than nixpkgs.
        package = lib.mkDefault flake.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.tuicr;
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

      aiSkills.extraSkills = lib.mkIf (cfg.enable && cfg.package != null) {
        tuicr = "${cfg.package.src}/skills/tuicr";
      };
    };
}
