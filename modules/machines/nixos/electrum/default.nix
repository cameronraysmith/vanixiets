{
  config,
  inputs,
  ...
}:
let
  # Capture outer config for use in imports
  flakeModules = config.flake.modules.nixos;
  flakeModulesHome = config.flake.modules.homeManager;
  flakeUsers = config.flake.users;
in
{
  # Export host module to flake namespace
  flake.modules.nixos."machines/nixos/electrum" =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      imports = [
        inputs.srvos.nixosModules.server
        inputs.srvos.nixosModules.hardware-hetzner-cloud
        inputs.home-manager.nixosModules.home-manager
      ]
      ++ (with flakeModules; [
        base
        hm-sops-bridge
        ssh-known-hosts
      ]);

      # Make flake available to all modules (required by ssh-known-hosts)
      _module.args.flake = inputs.self;

      # System platform
      nixpkgs.hostPlatform = "x86_64-linux";

      # ZFS device node path - more stable for cloud VMs
      boot.zfs.devNodes = "/dev/disk/by-path";

      # Disko disk configuration extracted to disko.nix
      # Auto-merged via import-tree

      # Bootloader: UEFI with systemd-boot (CCX23 has native UEFI support)
      # Force disable GRUB (srvos hardware-hetzner-cloud sets GRUB defaults for BIOS)
      boot.loader.grub.enable = lib.mkForce false;
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;

      # Hostname configuration
      networking.hostName = "electrum";

      networking.search = [ ];

      # Override state version for new deployment
      system.stateVersion = "25.05";

      # User configuration now managed via clan inventory users service
      # See: modules/clan/inventory/services/users.nix (user-cameron instance)
      # Provides: cameron user, wheel/networkmanager groups, zsh shell,
      #           home-manager integration, vars-based password management

      # Allow wheel group sudo without password
      security.sudo.wheelNeedsPassword = false;

      # Networking configuration
      # srvos hardware-hetzner-cloud sets useNetworkd=true and useDHCP=false
      # Configure primary interface with DHCP
      systemd.network.networks."10-uplink" = {
        matchConfig.Name = "en*";
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

      # Bridge NixOS-level sops to home-manager for user secret key delivery
      hm-sops-bridge.users.cameron.sopsIdentity = "crs58";

      # cameron home-manager imports (alias for crs58): all slots materialized
      # on flake.users.cameron by aliases-fold. Alias-keyed reads here keep
      # call sites ignorant of alias->target relationships; identityOverride
      # supplies the mkForce username/homeDirectory pinning.
      # Infrastructure settings (useGlobalPkgs, extraSpecialArgs, etc.) provided by cameron inventory service
      home-manager.users.cameron = {
        imports =
          flakeUsers.cameron.aggregates
          ++ [ flakeUsers.cameron.contentPrivate ]
          ++ [ flakeUsers.cameron.identityOverride ];
      };
    };
}
