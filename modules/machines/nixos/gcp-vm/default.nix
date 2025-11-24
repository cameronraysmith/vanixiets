{
  config,
  ...
}:
{
  # Export host module to flake namespace (dendritic pattern)
  flake.modules.nixos."machines/nixos/gcp-vm" =
    { ... }:
    {
      imports = with config.flake.modules.nixos; [ base ];

      # System platform
      nixpkgs.hostPlatform = "x86_64-linux";

      # Hostname configuration
      networking.hostName = "gcp-vm";

      # Override state version for new deployment
      system.stateVersion = "25.05";

      # Minimal system configuration
      # Additional configuration will be added for GCP terraform deployment
      boot.loader.grub.enable = true;
      boot.loader.grub.device = "/dev/sda";

      # Root filesystem (minimal required configuration)
      fileSystems."/" = {
        device = "/dev/sda1";
        fsType = "ext4";
      };

      # Basic networking
      networking.useDHCP = true;
    };
}
