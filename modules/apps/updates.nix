# Package update apps for packages with custom update scripts.
#
# Packages using nix-update-script do not need flake apps;
# invoke nix-update directly, e.g.:
#   nix-update --flake beads --version=branch=main
#
# nix run .#update-claude-code
{ ... }:
{
  perSystem =
    { config, ... }:
    {
      apps.update-claude-code = {
        type = "app";
        program = "${config.packages.claude-code.updateScript}";
      };

      apps.update-xsra = {
        type = "app";
        program = "${config.packages.xsra.updateScript}";
      };

      apps.update-beads-ui = {
        type = "app";
        program = "${config.packages.beads-ui.updateScript}";
      };

      apps.update-git-xet = {
        type = "app";
        program = "${config.packages.git-xet.updateScript}";
      };

      apps.update-duckdb = {
        type = "app";
        program = "${config.packages.duckdb.updateScript}";
      };
    };
}
