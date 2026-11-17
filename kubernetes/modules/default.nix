{ ... }:
{
  imports = [
    ./cluster-options.nix
    ./lib/namespace.nix
    ./argocd
    ./cilium
    ./gateway-api
    ./step-ca
    ./sops-secrets-operator
  ];
}
