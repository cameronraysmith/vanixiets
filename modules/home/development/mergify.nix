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

        # No configuration file is managed: every API-touching command resolves
        # its credential from MERGIFY_TOKEN, GITHUB_TOKEN, or a per-command
        # --token, so there is no non-secret settings surface to render.
      };
    };
}
