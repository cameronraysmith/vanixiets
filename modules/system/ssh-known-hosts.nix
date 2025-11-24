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
