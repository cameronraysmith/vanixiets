# Package update apps for packages with custom update scripts.
#
# Packages using nix-update-script do not need flake apps;
# invoke nix-update directly, e.g.:
#   nix-update --flake beads-next --version=branch=main
#   nix-update --flake dolt
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
    };
}
