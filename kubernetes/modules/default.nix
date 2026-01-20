{ ... }:
{
  imports = [
    ./cluster-options.nix
    ./argocd
    ./cilium
    ./step-ca
    ./sops-secrets-operator
  ];
}
