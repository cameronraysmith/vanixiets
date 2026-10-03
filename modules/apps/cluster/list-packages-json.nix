# list-packages-json.nix - Emit a JSON matrix of workspace packages.
#
# Enumerates packages/<name>/ directories whose package.json declares a
# non-null `release` key (explicit semantic-release opt-in) and emits a JSON
# array of {name, path} entries that the release-packages app iterates,
# calling the release app once per package path.
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
              pkgs.jq
            ];
            text = builtins.readFile ./list-packages-json.sh;
          }
        );
      };
    };
}
