# k3d-bootstrap-secrets.nix - Bootstrap sops-age-key into a running k3d cluster.
#
# Idempotent: second invocation leaves the secret byte-identical.
{ ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    {
      apps.k3d-bootstrap-secrets = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "k3d-bootstrap-secrets";
            runtimeInputs = [
              pkgs.bash
              pkgs.coreutils
              pkgs.kubectl
            ];
            text = builtins.readFile ./k3d-bootstrap-secrets.sh;
          }
        );
      };
    };
}
