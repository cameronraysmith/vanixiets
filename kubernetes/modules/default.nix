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

  # Required by easykubenix, with no default: the value kluctl deploys with as
  # its `--discriminator` (and `ekn kubeapply` stamps as `ekn.dev/environment`),
  # which scopes pruning. "easykubenix" is the value the removed
  # `kluctl.discriminator` default had, so live objects keep the label they
  # were deployed with.
  ekn.environment = "easykubenix";
}
