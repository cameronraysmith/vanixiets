{
  config,
  inputs,
  ...
}:
let
  # Capture outer config for use in imports
  flakeModules = config.flake.modules.nixos;
  flakeModulesHome = config.flake.modules.homeManager;
in
{
  # Export host module to flake namespace
  flake.modules.nixos."machines/nixos/magnetite" =
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
        inputs.srvos.nixosModules.mixins-nginx
        inputs.home-manager.nixosModules.home-manager
        inputs.niks3.nixosModules.niks3
        inputs.buildbot-nix.nixosModules.buildbot-master
        inputs.buildbot-nix.nixosModules.buildbot-worker
      ]
      ++ (with flakeModules; [
        base
        hm-sops-bridge
        niks3
        ssh-known-hosts
        buildbot
        gitea
        gitea-actions-runner
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
      # Auto-merged via import-tree

      # Bootloader: GRUB BIOS mode (CX53 has legacy BIOS only, not UEFI)
      # srvos hardware-hetzner-cloud handles GRUB BIOS configuration

      # Hostname configuration
      networking.hostName = "magnetite";

      networking.search = [ ];

      # Override state version for new deployment
      system.stateVersion = "25.05";

      # Compressed in-memory swap (zram) for effective memory extension
      zramSwap.enable = true;
      zramSwap.memoryPercent = 100;

      # User configuration managed via clan inventory users service
      # See: modules/clan/inventory/services/users/cameron.nix

      # Allow wheel group sudo without password
      security.sudo.wheelNeedsPassword = false;

      # ACME TLS certificate configuration for public-facing services
      security.acme = {
        acceptTerms = true;
        defaults.email = "cameron@scientistexperience.net";
      };

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

      # Firewall configuration: dual-zone (public + ZeroTier)
      networking.firewall = {
        enable = true;
        # Public-facing ports only
        allowedTCPPorts = [
          22
          80
          443
        ];
        # Admin and internal services accessible via ZeroTier only
        interfaces."zt+" = {
          allowedTCPPorts = [ ]; # populated by service modules later
        };
      };

      # SSH daemon configuration
      # Increase MaxAuthTries to accommodate agent forwarding with many keys
      # Default is 6, but Bitwarden SSH agent may have 10+ keys loaded
      services.openssh.settings.MaxAuthTries = 20;

      # Restricted builder user for remote nix builds (no sudo, SSH key only)
      users.users.builder = {
        isNormalUser = true;
        description = "Remote nix build user";
        openssh.authorizedKeys.keys = inputs.self.lib.userIdentities.crs58.sshKeys;
      };

      # Bridge NixOS-level sops to home-manager for user secret key delivery
      hm-sops-bridge.users.cameron.sopsIdentity = "crs58";

      # cameron home-manager module imports
      # Infrastructure settings (useGlobalPkgs, extraSpecialArgs, etc.) provided by cameron inventory service
      home-manager.users.cameron = {
        imports = [
          flakeModulesHome."users/crs58"
          flakeModulesHome.base-sops
          flakeModulesHome.ai
          flakeModulesHome.core
          flakeModulesHome.development
          flakeModulesHome.packages
          flakeModulesHome.shell
          flakeModulesHome.terminal
          flakeModulesHome.tools
          inputs.lazyvim-nix.homeManagerModules.default
          inputs.nix-index-database.homeModules.nix-index
          ../../../home/modules/_agents-md.nix
        ];
        home.username = "cameron";
      };
    };
}
