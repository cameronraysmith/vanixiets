# Package update apps for packages with custom update scripts.
#
# Packages using nix-update-script do not need flake apps;
# invoke nix-update directly, e.g.:
#   nix-update --flake <package> --version=branch=main
#
# Packages with a pin.json have no app here; they are realized with
# nix run .#realize-pin -- <package> <version>
#
# nix run .#update-xsra
{ ... }:
{
  perSystem =
    { config, ... }:
    {
      apps.update-xsra = {
        type = "app";
        program = "${config.packages.xsra.updateScript}";
      };
    };
}
