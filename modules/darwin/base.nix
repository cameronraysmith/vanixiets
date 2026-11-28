# The one definition of the darwin base: the parts every Mac imports.
# A part is a flake.modules.darwin module defined in one file and named here.
# A list option that two parts define merges their definitions in import
# order, so reordering the entries can change the hosts; package lists and the
# Brewfile's taps, brews and casks are sorted instead (system/package-order.nix).
{ config, ... }:
{
  flake.lib.darwinBaseParts = [
    "base-essentials"
    "base-etc-hosts"
    "base-homebrew"
    "base-launchd-wait4path"
    "base-nix-cleanup-gcroots"
    "base-nix-eval-jobs"
    "base-nix-settings"
    "base-pmset"
    "base-resolver-reload"
    "base-secure-input-watch"
    "base-sops-boot-install"
    "base-sshd-declaration"
    "base-system-defaults"
    "base-shared-vars-recipients"
    "base-source-context-obligations"
    "hm-sops-bridge"
    "base-nixpkgs"
    "base-caches"
    "cli-host-inspection"
    "base-commit-signing-key"
    "fleet-deploy-target"
    "base-harmonia-gc"
    "base-mesh-dns"
    "mesh-hosts"
    "base-mosh"
    "base-nix-download-timeout"
    "base-nix-optimization"
    "base-nix-package"
    "base-package-order"
    "secrets"
  ];
  flake.modules.darwin.base.imports = map (
    name: config.flake.modules.darwin.${name}
  ) config.flake.lib.darwinBaseParts;
}
