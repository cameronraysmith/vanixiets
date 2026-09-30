# list-packages-json.nix - Emit a JSON matrix of workspace packages.
#
# Enumerates packages/<name>/ directories containing a package.json
# and emits a JSON array of {name, path} entries that the release-packages
# app iterates, calling the release app once per package path.
{ ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    {
      apps.list-packages-json = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "list-packages-json";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.git
            ];
            text = builtins.readFile ./list-packages-json.sh;
          }
        );
      };
    };
}
