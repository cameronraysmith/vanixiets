# Declarative SSH known_hosts for critical infrastructure
# Prevents TOFU attacks on zerotier network and well-known services
# Hybrid approach:
#   - Static keys: GitHub, GitLab (external services) - srvos provides these
#   - Fleet hosts: flake.lib.hostKeys (modules/lib/host-keys.nix), the NixOS
#     hosts' committed clan sshd keys and the darwin hosts' pinned keys; no
#     other host's configuration is evaluated
#   - Static keys: the Termux phone
{ config, lib, ... }:
let
  inherit (config.flake.lib) hosts hostKeys;

  # Shared known_hosts configuration for all SSH clients
  # Any machine (NixOS or darwin) might connect to any infrastructure host
  # Single source of truth for zerotier network trust relationships
  knownHosts =
    lib.mapAttrs' (
      name: publicKey:
      lib.nameValuePair "${name}.zt" {
        hostNames = [
          "${name}.zt"
          hosts.${name}.zerotier.address
          hosts.${name}.fqdn
        ];
        inherit publicKey;
      }
    ) hostKeys
    // {
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
  flake.modules.nixos.ssh-known-hosts = {
    programs.ssh.knownHosts = knownHosts;
  };

  # Darwin module (identical configuration, different namespace)
  flake.modules.darwin.ssh-known-hosts = {
    programs.ssh.knownHosts = knownHosts;
  };
}
