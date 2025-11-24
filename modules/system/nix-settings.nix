{
  # Flake-parts module exporting to base namespace (merged with other base modules)
  flake.modules.nixos.base =
    { lib, ... }:
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

      # State version - update when migrating
      system.stateVersion = lib.mkDefault "24.11";
    };
}
