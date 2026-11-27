{ config, ... }:
let
  inherit (config.flake.lib) hosts;
in
{
  # Flake-parts module exporting to base namespace (merged with other base modules)
  flake.modules.nixos.base =
    { config, ... }:
    {
      # Nix settings for all machines
      nix = {
        settings = {
          experimental-features = [
            "nix-command"
            "flakes"
          ];
          trusted-users = [
            "root"
            "@wheel"
          ];
        };
      };

      # The host's state version, from its registry record
      # (flake.fleet.hosts.<host>.stateVersion, modules/lib/hosts.nix). Plain, so
      # it overrides clan-core's state-version module, which sets it at mkDefault
      # priority from the stored var.
      system.stateVersion = hosts.${config.networking.hostName}.stateVersion;
    };
}
