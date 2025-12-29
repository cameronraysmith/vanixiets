# Declarative SSH known_hosts for critical infrastructure
# Prevents TOFU attacks on zerotier network and well-known services
# Hybrid approach:
#   - Static keys: GitHub, GitLab (external services) - srvos provides these
#   - Dynamic keys: NixOS zerotier hosts via clan sshd vars
#   - Static keys: Darwin hosts (macOS system-managed)
{ lib, ... }:
let
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
          "fddb:4344:343b:14b9:399:93db:4344:343b" # Zerotier IPv6
        ];
        publicKey =
          flake.nixosConfigurations.cinnabar.config.clan.core.vars.generators.openssh.files."ssh.id_ed25519.pub".value;
      };

      "electrum.zt" = {
        hostNames = [
          "electrum.zt"
          "fddb:4344:343b:14b9:399:93d1:7e6d:27cc" # Zerotier IPv6
        ];
        publicKey =
          flake.nixosConfigurations.electrum.config.clan.core.vars.generators.openssh.files."ssh.id_ed25519.pub".value;
      };

      "galena.zt" = {
        hostNames = [
          "galena.zt"
          "fddb:4344:343b:14b9:399:9315:c67a:dec9" # Zerotier IPv6
        ];
        publicKey =
          flake.nixosConfigurations.galena.config.clan.core.vars.generators.openssh.files."ssh.id_ed25519.pub".value;
      };

      "scheelite.zt" = {
        hostNames = [
          "scheelite.zt"
          "fddb:4344:343b:14b9:399:9380:46d5:3400" # Zerotier IPv6
        ];
        publicKey =
          flake.nixosConfigurations.scheelite.config.clan.core.vars.generators.openssh.files."ssh.id_ed25519.pub".value;
      };

      # ====================
      # Darwin Machines (static SSH host keys)
      # ====================
      # Keys are macOS system-managed, not clan-generated
      # Extracted via: ssh-keyscan -t ed25519 <hostname>

      "blackphos.zt" = {
        hostNames = [
          "blackphos.zt"
          "fddb:4344:343b:14b9:399:930e:e971:d9e0" # Zerotier IPv6
        ];
        # Static key from /etc/ssh/ssh_host_ed25519_key.pub
        # Verified via ssh-keyscan blackphos.local 2025-11-19
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOWFgVKryKvWqDDsmUXKQYLFPQFfVXZj2S8E4TZsTtFc";
      };

      "stibnite.zt" = {
        hostNames = [
          "stibnite.zt"
          "fddb:4344:343b:14b9:399:933e:1059:d43a" # Zerotier IPv6
        ];
        # Static key from /etc/ssh/ssh_host_ed25519_key.pub
        # Verified 2025-11-29
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE+1b1qqnXJNhxANDyc17VqKo3SzDZSn+QlgLbh7sV2e";
      };

      "argentum.zt" = {
        hostNames = [
          "argentum.zt"
          "fddb:4344:343b:14b9:399:93f7:54d5:ad7e" # Zerotier IPv6
        ];
        # Static key from /etc/ssh/ssh_host_ed25519_key.pub
        # Verified 2025-11-29
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJB6ZUkT5+4U0kcfdOUMHo6qRV9qPlzkkCKj0C7Rqh2m";
      };

      "rosegold.zt" = {
        hostNames = [
          "rosegold.zt"
          "fddb:4344:343b:14b9:399:9315:3431:ee8" # Zerotier IPv6
        ];
        # Static key from /etc/ssh/ssh_host_ed25519_key.pub
        # Verified 2025-11-29
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII6X063DuDUFScs6Za6nx3TnvG9dlJDrTthx7e2aX1XA";
      };

      # ====================
      # Mobile Devices (Termux on Android)
      # ====================

      "pixel7.zt" = {
        hostNames = [
          "[pixel7.zt]:8022"
          "[fddb:4344:343b:14b9:399:939f:c45d:577c]:8022" # Zerotier IPv6 + Termux port
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
