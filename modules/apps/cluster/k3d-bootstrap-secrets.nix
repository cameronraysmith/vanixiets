# k3d-bootstrap-secrets.nix - Bootstrap sops-age-key into a running k3d cluster.
#
# Usage:
#   nix run .#k3d-bootstrap-secrets
#
# Template form: pure readFile (no nix-computed variable injection).
# Idempotent: second invocation leaves the secret byte-identical.
#
# Supports two key-source branches:
#   - SOPS_AGE_KEY env var present -> write to tmpfile, use
#   - otherwise                    -> read $HOME/.config/sops/age/keys.txt
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
