{
  config,
  inputs,
  ...
}:
let
  # Capture outer config for use in imports
  flakeModules = config.flake.modules.nixos;
  flakeUsers = config.flake.users;
in
{
  # Export host module to flake namespace
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

      # Bootloader: UEFI with systemd-boot (GCP defaults to UEFI since April 2020)
      boot.loader.grub.enable = lib.mkForce false;
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;

      # Hostname configuration
      networking.hostName = "galena";

      networking.search = [ ];

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

      # Bridge NixOS-level sops to home-manager for user secret key delivery
      hm-sops-bridge.users.cameron.sopsIdentity = "crs58";
      hm-sops-bridge.users.tara.sopsIdentity = "tara";

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

      # tara home-manager imports (ML researcher, no AI agent tooling):
      # aggregates + typed contentPrivate + identityOverride.
      home-manager.users.tara = {
        imports =
          flakeUsers.tara.aggregates
          ++ [ flakeUsers.tara.contentPrivate ]
          ++ [ flakeUsers.tara.identityOverride ];
        home.username = "tara";
        programs.agents-md.enable = false;
      };
    };
}
