# Declarative SSH known_hosts for critical infrastructure
# Prevents TOFU attacks on zerotier network and well-known services
# Hybrid approach:
#   - Static keys: GitHub, GitLab (external services) - srvos provides these
#   - Dynamic keys: NixOS zerotier hosts via clan sshd vars
#   - Static keys: Darwin hosts (macOS system-managed)
{ config, lib, ... }:
let
  inherit (config.flake.lib) hosts;

  # Shared known_hosts configuration for all SSH clients
  # Any machine (NixOS or darwin) might connect to any infrastructure host
  # Single source of truth for zerotier network trust relationships
  mkKnownHosts =
    flake:
    lib.optionalAttrs (flake ? nixosConfigurations) {
      # ====================
      # Zerotier Network (test-clan NixOS hosts)
      # ====================
      # Keys sourced from clan sshd service vars
      # Generated via: modules/clan/inventory/services/sshd.nix

      "cinnabar.zt" = {
        hostNames = [
          "cinnabar.zt"
          hosts.cinnabar.zerotier.address
          hosts.cinnabar.fqdn
        ];
        publicKey =
          flake.nixosConfigurations.cinnabar.config.clan.core.vars.generators.openssh.files."ssh.id_ed25519.pub".value;
      };

      "electrum.zt" = {
        hostNames = [
          "electrum.zt"
          hosts.electrum.zerotier.address
          hosts.electrum.fqdn
        ];
        publicKey =
          flake.nixosConfigurations.electrum.config.clan.core.vars.generators.openssh.files."ssh.id_ed25519.pub".value;
      };

      "galena.zt" = {
        hostNames = [
          "galena.zt"
          hosts.galena.zerotier.address
          hosts.galena.fqdn
        ];
        publicKey =
          flake.nixosConfigurations.galena.config.clan.core.vars.generators.openssh.files."ssh.id_ed25519.pub".value;
      };

      "scheelite.zt" = {
        hostNames = [
          "scheelite.zt"
          hosts.scheelite.zerotier.address
          hosts.scheelite.fqdn
        ];
        publicKey =
          flake.nixosConfigurations.scheelite.config.clan.core.vars.generators.openssh.files."ssh.id_ed25519.pub".value;
      };

      "magnetite.zt" = {
        hostNames = [
          "magnetite.zt"
          hosts.magnetite.zerotier.address
          hosts.magnetite.fqdn
        ];
        publicKey =
          flake.nixosConfigurations.magnetite.config.clan.core.vars.generators.openssh.files."ssh.id_ed25519.pub".value;
      };

      "pyrite.zt" = {
        hostNames = [
          "pyrite.zt"
          hosts.pyrite.zerotier.address
          hosts.pyrite.fqdn
        ];
        publicKey =
          flake.nixosConfigurations.pyrite.config.clan.core.vars.generators.openssh.files."ssh.id_ed25519.pub".value;
      };

      # ====================
      # Darwin Machines (static SSH host keys)
      # ====================
      # Keys are macOS system-managed, not clan-generated; pinned as static data in
      # flake.lib.darwinHostKeys (modules/lib/darwin-host-keys.nix)

      "blackphos.zt" = {
        hostNames = [
          "blackphos.zt"
          hosts.blackphos.zerotier.address
          hosts.blackphos.fqdn
        ];
        publicKey = config.flake.lib.darwinHostKeys.blackphos;
      };

      "stibnite.zt" = {
        hostNames = [
          "stibnite.zt"
          hosts.stibnite.zerotier.address
          hosts.stibnite.fqdn
        ];
        publicKey = config.flake.lib.darwinHostKeys.stibnite;
      };

      "argentum.zt" = {
        hostNames = [
          "argentum.zt"
          hosts.argentum.zerotier.address
          hosts.argentum.fqdn
        ];
        publicKey = config.flake.lib.darwinHostKeys.argentum;
      };

      "rosegold.zt" = {
        hostNames = [
          "rosegold.zt"
          hosts.rosegold.zerotier.address
          hosts.rosegold.fqdn
        ];
        publicKey = config.flake.lib.darwinHostKeys.rosegold;
      };

      # ====================
      # Mobile Devices (Termux on Android)
      # ====================

      "pixel7.zt" = {
        hostNames = [
          "[pixel7.zt]:8022"
          "[${hosts.pixel7.zerotier.address}]:8022" # Termux port
          # ssh checks the phone's key under the address its block dials
          # (modules/home/core/ssh.nix sets no HostKeyAlias for it).
          "[${hosts.pixel7.fqdn}]:8022"
          "[${hosts.pixel7.address}]:8022"
        ];
        # Static key from Termux openssh
        # Verified 2025-12-29
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBRGpKclkLskRxF+Iu4DTVkkLnAk5cBipL0dDtrvROwJ";
      };
    };
in
{
  # NixOS module (system-level SSH client configuration)
  flake.modules.nixos.ssh-known-hosts =
    { flake, ... }:
    {
      programs.ssh.knownHosts = mkKnownHosts flake;
    };

  # Darwin module (identical configuration, different namespace)
  flake.modules.darwin.ssh-known-hosts =
    { flake, ... }:
    {
      programs.ssh.knownHosts = mkKnownHosts flake;
    };
}
