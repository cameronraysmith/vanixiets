# easykubenix modules index
#
# Imports all Kubernetes modules for cluster configuration.
{ ... }:
{
  imports = [
    ./cluster-options.nix
    ./cilium
  ];
}
