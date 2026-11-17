# ctlptl configuration of the local k3d cluster, rendered from
# kubernetes/clusters/local-k3d/ctlptl.nix so its node image follows the
# locked nixpkgs k3s. The k3d-up and k3d-down just recipes build it and pass
# the store path to `ctlptl apply/delete -f`.
#
# Usage:
#   nix build .#k3d-cluster-config
{ ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    {
      packages.k3d-cluster-config = pkgs.writeText "k3d-cluster-config.json" (
        builtins.toJSON (
          import ../kubernetes/clusters/local-k3d/ctlptl.nix {
            inherit lib;
            inherit (pkgs) k3s;
          }
        )
      );
    };
}
