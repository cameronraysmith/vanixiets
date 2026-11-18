# Firewall interface keys of every overlay a NixOS host carries: ZeroTier's
# backend-specific key until ZeroTier is retired, and the tincr interface.
{ config, ... }:
let
  inherit (config.flake.lib) mesh zerotierInterfaces;
in
{
  flake.lib.meshInterfaces = nixosConfig: [
    (zerotierInterfaces nixosConfig)
    mesh.interface.nixos
  ];
}
