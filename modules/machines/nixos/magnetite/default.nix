{
  config,
  inputs,
  ...
}:
let
  flakeModules = config.flake.modules.nixos;
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
        kanidm
        matrix
        effects-vanixiets-secrets
        effects-ironstar-secrets
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

      # systemd-nspawn-flavor NixOS tests require uid-range, auto-allocate-uids, and cgroups.
      # See nixos/doc/manual/development/running-nixos-tests.section.md in nixpkgs.
      nix.settings = {
        auto-allocate-uids = true;
        extra-system-features = [ "uid-range" ];
        experimental-features = [
          "auto-allocate-uids"
          "cgroups"
        ];
      };

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

      # Tune ZFS auto-snapshot retention for a single-disk cloud VPS without
      # off-site snapshot replication. The nixpkgs defaults (frequent=4,
      # hourly=24, daily=7, weekly=4, monthly=1 via srvos mkDefault) are
      # calibrated for workstations with USB backup targets and produce
      # excessive snapshot churn on a cloud node. `/nix` is opted out via
      # the disko `com.sun:auto-snapshot=false` property; the remaining
      # datasets (/nixos, /home, /docker, /podman) retain a short window.
      services.zfs.autoSnapshot = {
        frequent = 0;
        hourly = 4;
        daily = 3;
        weekly = 1;
        monthly = lib.mkForce 0;
      };

      # Disko's `options."com.sun:auto-snapshot" = "false"` on reproducible-content
      # datasets (root/nix, root/docker, root/podman; see disko.nix) is honored only
      # at dataset CREATION time. For already-provisioned hosts, the property is not
      # re-asserted by `nixos-rebuild switch` or `clan machines update`. These oneshots
      # make the declared intent a runtime invariant by issuing `zfs set` at boot.
      # `zfs set` is a no-op when the value already matches, so the units are
      # idempotent and side-effect-free on repeat boots.
      systemd.services.zfs-assert-root-nix-noautosnap = {
        description = "Assert com.sun:auto-snapshot=false on zroot/root/nix";
        wantedBy = [ "multi-user.target" ];
        after = [ "zfs-import.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.zfs}/bin/zfs set com.sun:auto-snapshot=false zroot/root/nix";
        };
      };

      systemd.services.zfs-assert-root-docker-noautosnap = {
        description = "Assert com.sun:auto-snapshot=false on zroot/root/docker";
        wantedBy = [ "multi-user.target" ];
        after = [ "zfs-import.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.zfs}/bin/zfs set com.sun:auto-snapshot=false zroot/root/docker";
        };
      };

      systemd.services.zfs-assert-root-podman-noautosnap = {
        description = "Assert com.sun:auto-snapshot=false on zroot/root/podman";
        wantedBy = [ "multi-user.target" ];
        after = [ "zfs-import.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.zfs}/bin/zfs set com.sun:auto-snapshot=false zroot/root/podman";
        };
      };

      # Pool-starvation guardrails (2026-06-10 incident: /nix consumed the
      # entire 304G pool and wedged every dataset). The quota caps /nix below
      # pool capacity; the reservations guarantee / and /home writable
      # headroom even when /nix hits its quota. Mirrored create-time in
      # disko.nix; these oneshots enforce the values on the already-
      # provisioned host because disko options apply at dataset creation only.
      systemd.services.zfs-set-root-nix-quota = {
        description = "Assert quota=250G on zroot/root/nix";
        wantedBy = [ "multi-user.target" ];
        after = [ "zfs-import.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.zfs}/bin/zfs set quota=250G zroot/root/nix";
        };
      };

      systemd.services.zfs-set-root-nixos-reservation = {
        description = "Assert reservation=10G on zroot/root/nixos";
        wantedBy = [ "multi-user.target" ];
        after = [ "zfs-import.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.zfs}/bin/zfs set reservation=10G zroot/root/nixos";
        };
      };

      systemd.services.zfs-set-root-home-reservation = {
        description = "Assert reservation=4G on zroot/root/home";
        wantedBy = [ "multi-user.target" ];
        after = [ "zfs-import.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.zfs}/bin/zfs set reservation=4G zroot/root/home";
        };
      };

      # Raise nix daemon free-space thresholds for a build host. clan-core and
      # srvos both set 512 MiB / 3 GiB via mkDefault, which is undersized for
      # buildbot-nix workers materializing large closures on a CX53 with niks3
      # GC pressure. Trigger GC at 30 GiB free, free until 80 GiB available.
      nix.settings = {
        min-free = 30 * 1024 * 1024 * 1024;
        max-free = 80 * 1024 * 1024 * 1024;
      };

      # base sets nix.gc.options fleet-wide as a plain string (modules/system/
      # nix-optimization.nix), so this host-level tightening requires mkForce.
      # Build outputs persist in the niks3 R2 cache; short local retention is
      # safe on the build host.
      nix.gc.options = lib.mkForce "--delete-older-than 7d";

      # Nix >= 2.30 keeps build sandboxes in /nix/var/nix/builds; the only
      # reaper is the Nix package's tmpfiles rule (nix-daemon.conf, age 7d).
      # A 7d window let a nix-daemon ENOSPC crash-loop orphan 201 sandboxes
      # (232 GiB) on 2026-06-10. This entry renders into 00-nixos.conf, which
      # sorts before nix-daemon.conf, so per tmpfiles.d(5) precedence the 1d
      # age wins for this path. Active sandboxes (<= 3h buildbot hard
      # timeout) never enter the 1d window.
      systemd.tmpfiles.rules = [
        "d /nix/var/nix/builds 0755 root root 1d -"
      ];

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
        openssh.authorizedKeys.keys = inputs.self.users.crs58.meta.sshKeys;
      };

      # Bridge NixOS-level sops to home-manager for user secret key delivery.
      # sopsIdentity defaults to flake.users.cameron.meta.sopsAgeKeyId
      # ("crs58" via alias-fold inheritance).
      hm-sops-bridge.users.cameron = { };

      # cameron is an alias for crs58; alias-keyed reads keep this
      # call site ignorant of the alias->target relationship.
      # Infrastructure settings provided by the cameron inventory service.
      home-manager.users.cameron = {
        imports = flakeUsers.cameron.modules;
      };
    };
}
