# Darwin host SSH keys, as static flake data. macOS manages these keys, so
# unlike the NixOS hosts' clan-generated keys they are pinned here as literals:
# flake.lib.hostKeys (modules/lib/host-keys.nix) merges them with the NixOS
# hosts' committed keys, and modules/system/ssh-known-hosts.nix reads that for
# known_hosts; modules/checks/sops-correspondence.nix compares the ssh-to-age
# image of each host that has a .sops.yaml anchor (blackphos) with that
# anchor, without evaluating any host configuration.
# Each value is /etc/ssh/ssh_host_ed25519_key.pub on the host.
{ ... }:
{
  flake.lib.darwinHostKeys = {
    # Verified via ssh-keyscan blackphos.local 2025-11-19
    blackphos = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOWFgVKryKvWqDDsmUXKQYLFPQFfVXZj2S8E4TZsTtFc";
    # Verified 2026-07-10 (rehomed to new hardware)
    stibnite = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA7eyzXKTI0pjLl1hbU8UuM3VFWq2NqYdf7cBPCcC638";
    # Verified 2025-11-29
    argentum = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJB6ZUkT5+4U0kcfdOUMHo6qRV9qPlzkkCKj0C7Rqh2m";
    # Verified 2025-11-29
    rosegold = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII6X063DuDUFScs6Za6nx3TnvG9dlJDrTthx7e2aX1XA";
  };
}
