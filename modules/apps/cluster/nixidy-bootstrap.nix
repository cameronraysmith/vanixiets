# nixidy-bootstrap.nix - Apply the local-k3d app-of-apps bootstrap Application CR.
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
      apps.nixidy-bootstrap = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "nixidy-bootstrap";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.kubectl
              config.packages.nixidy
            ];
            text = builtins.readFile ./nixidy-bootstrap.sh;
          }
        );
      };
    };
}
