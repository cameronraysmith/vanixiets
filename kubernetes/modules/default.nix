{ ... }:
{
  imports = [
    ./cluster-options.nix
    ./cilium
    ./step-ca
    ./sops-secrets-operator
  ];
}
