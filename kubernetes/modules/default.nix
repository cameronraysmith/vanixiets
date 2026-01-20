{ ... }:
{
  imports = [
    ./cluster-options.nix
    ./argocd
    ./cilium
    ./gateway-api
    ./step-ca
    ./sops-secrets-operator
  ];
}
