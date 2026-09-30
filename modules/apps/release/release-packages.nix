# release-packages.nix - release every monorepo package at a main rev, or
# forecast a pull request's releases as the release-plan check run.
#
#   nix run .#release-packages -- --rev <40-hex>
#   nix run .#release-packages -- plan
#
# The program the release-packages effect executes; release-rehearsal runs it
# against a local GitHub stand-in. list-packages-json, release,
# github-check-run and github-pull-request are passed as store paths because
# the effect sandbox binds no working tree for `.#`.
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
              pkgs.gnused
              pkgs.gnugrep
            ];
            runtimeEnv = {
              RELEASE_PACKAGES_LIST = config.apps.list-packages-json.program;
              RELEASE_PACKAGES_RELEASE = config.apps.release.program;
              RELEASE_PACKAGES_CHECK_RUN = config.apps.github-check-run.program;
              RELEASE_PACKAGES_PULL_REQUEST = config.apps.github-pull-request.program;
            };
            text = builtins.readFile ./release-packages.sh;
          }
        );
      };
    };
}
