{
  config,
  inputs,
  ...
}:
let
  flakeModules = config.flake.modules.nixos;
  flakeModulesHome = config.flake.modules.homeManager;
  flakeUsers = config.flake.users;
in
{
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
        docker
        effects-vanixiets-secrets
      ]);

      # Make flake available to all modules (required by ssh-known-hosts)
      _module.args.flake = inputs.self;

      nixpkgs.hostPlatform = "x86_64-linux";

      # ZFS device node path - more stable for cloud VMs
      boot.zfs.devNodes = "/dev/disk/by-path";

      # Bootloader: GRUB BIOS mode (CX53 has legacy BIOS only, not UEFI)
      # srvos hardware-hetzner-cloud handles GRUB BIOS configuration

      networking.hostName = "magnetite";

      networking.search = [ ];

      system.stateVersion = "25.05";

      # User configuration managed via clan inventory users service (modules/clan/inventory/services/users/cameron.nix).

      security.sudo.wheelNeedsPassword = false;

      security.acme = {
        acceptTerms = true;
        defaults.email = "cameron@scientistexperience.net";
      };

      # srvos mixins-nginx enables the deprecated security.dhparams module
      # (removed in NixOS 26.11); DHE cipher suites have no real consumer.
      services.nginx.sslDhparam = lib.mkForce false;
      security.dhparams.enable = lib.mkForce false;

      # srvos hardware-hetzner-cloud sets useNetworkd=true and useDHCP=false; configure primary interface explicitly.
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

      # cameron home-manager imports (alias for crs58): all slots materialized
      # on flake.users.cameron by aliases-fold. Alias-keyed reads here keep
      # call sites ignorant of alias->target relationships; identityOverride
      # supplies the mkForce username/homeDirectory pinning.
      # Infrastructure settings provided by the cameron inventory service.
      home-manager.users.cameron = {
        imports =
          flakeUsers.cameron.aggregates
          ++ [ flakeUsers.cameron.contentPrivate ]
          ++ [ flakeUsers.cameron.identityOverride ];
      };
    };
}
