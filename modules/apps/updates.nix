# Package update apps for packages with custom update scripts.
#
# Packages using nix-update-script do not need flake apps;
# invoke nix-update directly, e.g.:
#   nix-update --flake <package> --version=branch=main
#
# Packages with a pin.json have no app here; they are realized with
# nix run .#realize-pin -- <package> <version>
#
# nix run .#update-atomic
{ ... }:
{
  perSystem =
    { config, ... }:
    {
      apps.update-atomic = {
        type = "app";
        program = "${config.packages.atomic.updateScript}";
      };

      apps.update-pi-acp = {
        type = "app";
        program = "${config.packages.pi-acp.updateScript}";
      };

      apps.update-devin-cli = {
        type = "app";
        program = "${config.packages.devin-cli.updateScript}";
      };

      apps.update-xsra = {
        type = "app";
        program = "${config.packages.xsra.updateScript}";
      };

      # perses-bin exists only on x86_64-linux and aarch64-darwin (its
      # package.nix yields null on aarch64-linux); the updater is
      # host-agnostic, so the app runs the script itself on every system.
      apps.update-perses-bin = {
        type = "app";
        program = "${../../pkgs/by-name/perses-bin/update.sh}";
      };

      apps.update-buzz-source = {
        type = "app";
        program = "${config.packages.buzz-source.updateScript}";
      };
    };
}
