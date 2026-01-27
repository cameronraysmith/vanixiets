# ZeroTier service DNS entries for clawdbot infrastructure
{ ... }:
{
  flake.modules.nixos."machines/nixos/cinnabar" = {
    networking.extraHosts = ''
      fddb:4344:343b:14b9:399:93db:4344:343b matrix.zt
      fddb:4344:343b:14b9:399:93db:4344:343b clawdbot.zt
    '';
  };
}
