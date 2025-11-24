{ config, ... }:
{
  flake.modules.darwin."machines/darwin/test-darwin" =
    { ... }:
    {
      imports = with config.flake.modules.darwin; [
        base
        users
      ];

      # Host-specific configuration
      networking.hostName = "test-darwin";
      networking.computerName = "test-darwin";

      # Platform
      nixpkgs.hostPlatform = "aarch64-darwin";
    };
}
