{ ... }:
{
  imports = [
    ./cluster-options.nix
    ./lib/namespace.nix
    ./argocd
    ./cilium
    ./step-ca
    ./sops-secrets-operator
  ];
}
