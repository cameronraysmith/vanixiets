# Admin user for legacy machines (forced username). The clan users service's
# settings apply to NixOS only. The home-manager integration and the home
# come from the host's attachment (modules/system/home-manager-integration.nix).
{ config, ... }:
{
  flake.clan.inventory.instances.user-crs58 = config.flake.lib.mkUserInstance {
    user = "crs58";
    groups = [
      "wheel" # sudo access
      "networkmanager" # network configuration
    ];
  };
}
