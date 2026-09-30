{ config, ... }:
{
  flake.modules.homeManager.development.imports = [ config.flake.modules.homeManager.mergify ];
  flake.modules.homeManager.mergify =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.mergify;
    in
    {
      key = "vanixiets/mergify-home-module";

      options.programs.mergify = {
        enable = lib.mkEnableOption "the Mergify CLI, whose `mergify stack` subcommand drives stacked-pull-request landing";

        package = lib.mkPackageOption pkgs "mergify-cli-bin" { };
      };

      config = {
        programs.mergify.enable = lib.mkDefault true;

        home.packages = lib.mkIf cfg.enable [ cfg.package ];

        # No configuration file is managed, so there is no non-secret settings
        # surface to render. Non-stack commands resolve their credential from
        # --token, then MERGIFY_TOKEN, then the OS-keychain credential stored
        # by `mergify auth login`, then GITHUB_TOKEN, then `gh auth token`
        # (the last two print a deprecation warning). `mergify stack` commands
        # are unaffected and keep --token, MERGIFY_TOKEN, GITHUB_TOKEN,
        # `gh auth token`.
      };
    };
}
