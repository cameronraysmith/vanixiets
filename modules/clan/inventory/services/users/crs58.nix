# Admin user for legacy machines (forced username)
# Clan users service settings apply to NixOS only. The home-manager
# integration and the home come from the host's attachment
# (modules/system/home-manager-integration.nix).
{
  config,
  lib,
  ...
}:
{
  flake.clan.inventory.instances.user-crs58 = {
    module = {
      name = "users";
      input = "clan-core";
    };

    # Every host with a crs58 attachment (modules/lib/host-users.nix)
    roles.default.machines = lib.genAttrs (config.flake.lib.hostsOfAccount "crs58") (_: { });

    roles.default.settings = {
      user = "crs58";
      groups = [
        "wheel" # sudo access
        "networkmanager" # network configuration
      ];
      share = true; # Same password as cameron instances (nixos only currently)
      prompt = false; # Auto-generate password via xkcdpass (nixos only currently)
    };
  };
}
