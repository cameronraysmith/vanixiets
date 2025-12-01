{
  config,
  inputs,
  ...
}:
let
  # Capture outer config for use in imports
  flakeModules = config.flake.modules.nixos;
in
{
  # Export host module to flake namespace (dendritic pattern)
  flake.modules.nixos."machines/nixos/galena" =
    {
      config,
      lib,
      ...
    }:
    {
      imports = [
        inputs.srvos.nixosModules.server
        # NOTE: Do NOT import srvos.hardware-hetzner-cloud (Hetzner-specific)
        inputs.home-manager.nixosModules.home-manager
      ]
      ++ (with flakeModules; [
        base
        ssh-known-hosts
      ]);

      # Make flake available to all modules (required by ssh-known-hosts)
      _module.args.flake = inputs.self;

      # System platform
      nixpkgs.hostPlatform = "x86_64-linux";

      # Allow unfree packages for nixosConfigurations (clan CLI path)
      # perSystem.legacyPackages only affects clanInternals.machines (nom build path)
      nixpkgs.config.allowUnfree = true;

      # Use flake.overlays.default (drupol pattern)
      # All 5 overlay layers + pkgs-by-name packages exported from modules/nixpkgs.nix
      nixpkgs.overlays = [ inputs.self.overlays.default ];

      # ZFS device node path - more stable for cloud VMs
      boot.zfs.devNodes = "/dev/disk/by-path";

      # Disko disk configuration extracted to disko.nix
      # Auto-merged via dendritic flake-parts pattern

      # Bootloader: UEFI with systemd-boot (GCP defaults to UEFI since April 2020)
      boot.loader.grub.enable = lib.mkForce false;
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;

      # Hostname configuration
      networking.hostName = "galena";

      # Override state version for new deployment
      system.stateVersion = "25.05";

      # User configuration managed via clan inventory users service

      # Allow wheel group sudo without password
      security.sudo.wheelNeedsPassword = false;

      # Networking configuration
      # Configure networkd for GCP VMs
      networking.useNetworkd = true;
      networking.useDHCP = false;
      systemd.network.networks."10-uplink" = {
        matchConfig.Name = "en* eth*";
        networkConfig = {
          DHCP = "yes";
          IPv6AcceptRA = true;
        };
        dhcpV4Config.UseDNS = true;
        dhcpV6Config.UseDNS = true;
      };

      # Firewall configuration
      networking.firewall = {
        enable = true;
        # Allow SSH (configured by srvos.nixosModules.server)
        # Additional ports can be opened as needed
      };

      # SSH daemon configuration
      # Increase MaxAuthTries to accommodate agent forwarding with many keys
      # Default is 6, but Bitwarden SSH agent may have 10+ keys loaded
      services.openssh.settings.MaxAuthTries = 20;
    };
}
