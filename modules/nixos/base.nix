# The one definition of the NixOS base: the parts every NixOS host imports.
# A part is a flake.modules.nixos module defined in one file and named here.
# A list option that two parts define, such as nix substituters, merges their
# definitions in import order, so reordering the entries can change the hosts;
# system packages are sorted instead (system/package-order.nix).
{ config, ... }:
{
  flake.lib.nixosBaseParts = [
    "base-host-keys"
    "base-shared-vars-recipients"
    "base-source-context-obligations"
    "hm-sops-bridge"
    "nix-build-lock"
    "nix-eval-lock"
    "node-exporter-textfile"
    "postgresql-collation"
    "zpool-probe"
    "base-nixpkgs"
    "base-admins"
    "base-caches"
    "cli-host-inspection"
    "base-commit-signing-key"
    "fleet-deploy-target"
    "base-harmonia-gc"
    "base-mesh-dns"
    "mesh-hosts"
    "base-mosh"
    "base-nix-cleanup-gcroots"
    "base-nix-download-timeout"
    "base-nix-optimization"
    "base-nix-package"
    "base-nix-settings"
    "base-nix-tarmac"
    "base-package-order"
    "secrets"
    "base-command-not-found"
    "base-sshd-max-auth-tries"
    "base-zfs-force-import"
    "base-zfs-hm-ordering"
    "base-zram-swap"
  ];
  flake.modules.nixos.base.imports = map (
    name: config.flake.modules.nixos.${name}
  ) config.flake.lib.nixosBaseParts;
}
