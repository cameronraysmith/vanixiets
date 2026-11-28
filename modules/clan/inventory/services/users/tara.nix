# External ML researcher on the GPU and CPU cloud nodes
{ config, ... }:
{
  flake.clan.inventory.instances.user-tara = config.flake.lib.mkUserInstance {
    user = "tara";
    groups = [
      "video" # GPU device access
      "render" # GPU render node access
    ];
    shellAndKeys = true;
  };
}
