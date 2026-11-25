# nix run .#realize-pin -- <package> <version>
# Renovate's single post-upgrade task for package pins (automate-package-version-bumps design D7).
{ ... }:
{
  perSystem =
    { config, lib, ... }:
    {
      apps.realize-pin = {
        type = "app";
        program = lib.getExe config.packages.realize-pin;
        meta.description = "Rewrite a package's pin.json and its typed companion files for one version";
      };
    };
}
