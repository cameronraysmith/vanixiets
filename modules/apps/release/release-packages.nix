# release-packages.nix - release every monorepo package at a main rev.
#
#   nix run .#release-packages -- --rev <40-hex>
#
# The program the release-packages effect executes; release-rehearsal runs it
# against a local GitHub stand-in. list-packages-json and release are passed
# as store paths because the effect sandbox binds no working tree for `.#`.
{ ... }:
{
  perSystem =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    {
      apps.release-packages = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "release-packages";
            runtimeInputs = [
              pkgs.git
              pkgs.jq
              pkgs.coreutils
            ];
            runtimeEnv = {
              RELEASE_PACKAGES_LIST = config.apps.list-packages-json.program;
              RELEASE_PACKAGES_RELEASE = config.apps.release.program;
            };
            text = builtins.readFile ./release-packages.sh;
          }
        );
      };
    };
}
