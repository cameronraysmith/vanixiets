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
  flake.modules.nixos."machines/nixos/pyrite" =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      imports = [
        inputs.home-manager.nixosModules.home-manager
        inputs.nixos-hardware.nixosModules.apple-macbook-pro-14-1
      ]
      ++ (with flakeModules; [
        base
        hm-sops-bridge
        ssh-known-hosts
      ]);

      # Make flake available to all modules (required by ssh-known-hosts)
      _module.args.flake = inputs.self;

      # System platform (Kaby Lake, Intel Iris Plus 640)
      nixpkgs.hostPlatform = "x86_64-linux";

      # Bootloader: UEFI with systemd-boot. canTouchEfiVariables writes the machine's
      # 8 MiB SPI boot ROM (not the disk the install wipes); an EFI write failing is
      # recoverable by an NVRAM reset, not a brick.
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;

      # by-id, not the fleet's by-path: the "more stable for cloud VMs" reasoning does
      # not transfer to a laptop with a stable by-id path, and by-id is the bare-metal
      # norm. ZFS scanning the 8 KiB nvme0n2 namespace on import is harmless; the hazard
      # is a write, and only the disko device writes. See D3.
      boot.zfs.devNodes = "/dev/disk/by-id";

      networking.hostName = "pyrite";

      # Matches the 26.05 installer ISO release this machine is installed from. Never
      # change after install. This plain assignment overrides clan-core's state-version
      # module, which sets system.stateVersion at mkDefault priority from the stored var
      # (clan-core nixosModules/clanCore/state-version/default.nix:18), so the committed
      # vars/per-machine/pyrite/state-version/version/value does not affect evaluation.
      system.stateVersion = "26.05";

      # Kept from base as a deliberate decision, not an inheritance (D6): an install
      # re-run touches the pool from the installer environment, and importing without
      # force after that lands the next boot in an emergency shell, which would defeat
      # this change's re-runnable-install acceptance criterion. Value equals base's, so
      # this restatement conflicts with nothing.
      boot.zfs.forceImportRoot = true;

      # networking.hostId: deliberately unset (D7). Inherit clan-core's
      # mkDefault "8425e349" (nixosModules/clanCore/zfs.nix:10), which matches the
      # install ISO and nixos-anywhere so the installer that creates the pool and the
      # system that imports it present the same hostid. Pinning a machine-specific
      # hostid would manufacture the mismatch that default exists to prevent.

      # boot.plymouth: deliberately left at its default false (D11). plymouth swaps the
      # passphrase prompt onto a different ask-password agent
      # (systemd-ask-password-console does not start while /run/plymouth/pid exists) and
      # a graphical stack whose interaction with i915 on this model is unverified. The
      # prompt is this machine's safety-critical path.

      # Disabling initrd networking itself, not just its ssh sub-option, is what keeps
      # brcmfmac out of the initrd: nixpkgs' hardware/facter/networking/initrd.nix:18 gates
      # its boot.initrd.kernelModules assignment on boot.initrd.network.enable, and it is the
      # sole definition site injecting this machine's NIC driver there. Force-loading
      # brcmfmac in stage 1 against the shrunken module tree leaves the request_module for
      # the per-vendor brcmfmac-wcc sub-module unsatisfiable, and brcmf_fwvid_attach's error
      # path then calls device_release_driver, unbinding the PCI device permanently — the
      # machine boots with no wifi device at all, and it has no other NIC. mkForce because
      # base sets enable = true plainly. This subsumes ssh.enable: initrd-ssh.nix's `enabled`
      # is (network.enable || systemd.network.enable) && cfg.enable, so initrd ssh stays off,
      # which is what the design's base-initrd-assumptions section wanted and what its
      # ssh-only override failed to reach. This is a distinct option from
      # boot.initrd.kernelModules, which MUST NOT be mkForce'd (see the design's invariant):
      # the SPI keyboard and i915 modules carrying the stage-1 passphrase prompt must
      # survive.
      boot.initrd.network.enable = lib.mkForce false;

      # b43 is a silicon misdetection, not an evaluation workaround: enableB43Firmware
      # pulls b43Firmware_5_1_138 for the SoftMAC BCM43xx parts, but this machine's NIC
      # is a BCM4350 driven by brcmfmac, which that firmware does not serve. allowUnfree
      # is true fleet-wide so it evaluates; it is declined for the wrong silicon. Plain
      # false overrides the profile's lib.mkDefault true. See D5.
      networking.enableB43Firmware = false;
      # The FaceTime HD camera is out of scope. The fleet's allowUnfree would resolve the
      # profile's mkDefault to true, auto-enabling an out-of-tree kernel module and unfree
      # firmware on import; plain false keeps both out of the closure.
      hardware.facetimehd.enable = false;

      # Stated explicitly, not inherited from facter's bare-metal mkDefault branch (dead
      # on every existing cloud VM). The axis is redistributability, not freeness:
      # enableRedistributableFirmware puts linux-firmware into hardware.firmware
      # (all-firmware.nix:71-86,75), and linux-firmware carries the
      # brcm/brcmfmac4350*-pcie.bin blobs this machine's only NIC needs in order to probe.
      # false darkens the WiFi (its own default is enableAllFirmware, i.e. false).
      # linux-firmware is a redistributable proprietary blob that caches serve, so this is
      # not the decline 2.2 applies to non-redistributable firmware. See D15.
      hardware.enableRedistributableFirmware = true;
      hardware.cpu.intel.updateMicrocode = true;

      # The model profile sets services.mbpfan.enable via mkDefault true, and mbpfan is
      # wanted (D16); restating a plain true would only echo the default. The profile also
      # sets services.tlp.enable = mkDefault (!config.services.power-profiles-daemon.enable),
      # and the GNOME desktop below enables power-profiles-daemon (D19), so tlp evaluates
      # false and power-profiles-daemon is this machine's power-management governor. The
      # module writes neither enable, forcing tlp neither on nor off. The one line the
      # module needs is the quieter fan curve: mbpfan's own aggressive default is true
      # (thresholds 55/58/78); false takes them to 63/66/86 and is the only user-visible
      # consequence of the daemon. mbpfan is not a 2.2-style decline: its license is gpl3
      # (free, redistributable, in-tree, cache-served), and beyond the applesmc the profile
      # already force-loads it adds only coretemp.
      services.mbpfan.aggressive = false;

      # Suspend is broken on this hardware in both available sleep states, so the lid must
      # not reach the suspend path. Deep S3 (the kernel default here) hangs immediately:
      # two recorded attempts each ended their boot at "PM: suspend entry (deep)" with no
      # resume line. s2idle resumes the kernel and briefly restores networking, but the
      # display never comes back and the machine dies about a minute later. This machine's
      # only remote access is ZeroTier over WiFi and it cannot be rebooted remotely
      # (initrd networking is disabled above and the ZFS root needs a typed passphrase at
      # stage 1), so a lid-triggered suspend costs physical intervention. lock keeps the
      # session locked while the machine stays up. These are the current option names;
      # services.logind.lidSwitch* are settingsRename aliases (nixpkgs
      # nixos/modules/system/boot/systemd/logind.nix:104-106).
      services.logind.settings.Login = {
        HandleLidSwitch = "lock";
        HandleLidSwitchExternalPower = "lock";
        HandleLidSwitchDocked = "ignore";
      };

      # NVMe d3cold workaround (D21). The nixos-hardware profile ships this service
      # commented out under "[Enable only if needed!]" (apple/macbook-pro/14-1/default.nix:60-68),
      # so importing the profile does not activate it; pyrite defines its own. The
      # observable is that /sys/.../0000:01:00.0/d3cold_allowed reads 0, not the oneshot's
      # is-active state. The upstream script runs unmodified: its :5-7 exits 1 (logged) when
      # 0000:01:00.0 is absent, the failure worth having. Its :12 driver guard is inert
      # (`[[ "$driver" -ne "nvme" ]]` is bash arithmetic, 0 -ne 0, always false), so it never
      # fires and is not relied upon; only the :5-7 address check is.
      systemd.services.disable-nvme-d3cold = {
        description = "Disables d3cold on the NVME controller";
        before = [ "suspend.target" ];
        path = [
          pkgs.bash
          pkgs.coreutils
        ];
        serviceConfig.Type = "oneshot";
        serviceConfig.ExecStart = "${inputs.nixos-hardware}/apple/macbook-pro/14-1/disable-nvme-d3cold.sh";
        serviceConfig.TimeoutSec = 0;
        wantedBy = [
          "multi-user.target"
          "suspend.target"
        ];
      };

      # Suspend interlock, fail-closed: a failed Requires dependency aborts the requiring
      # unit's start job, so a nonzero exit here aborts systemd-suspend.service (and the
      # hybrid variants with an S3 leg) rather than letting the machine suspend with the
      # workaround inactive and hang.
      systemd.services.nvme-d3cold-suspend-guard =
        let
          sleepUnits = [
            "systemd-suspend.service"
            "systemd-hybrid-sleep.service"
            "systemd-suspend-then-hibernate.service"
          ];
        in
        {
          description = "Refuse suspend unless NVMe d3cold is disabled";
          before = sleepUnits;
          requiredBy = sleepUnits;
          serviceConfig = {
            Type = "oneshot";
            ExecStart = pkgs.writeShellScript "nvme-d3cold-suspend-guard" ''
              d3cold=/sys/bus/pci/devices/0000:01:00.0/d3cold_allowed
              if [[ "$(cat "$d3cold" 2>/dev/null)" != 0 ]]; then
                echo "refusing suspend: $d3cold is not 0, d3cold workaround is inactive" >&2
                exit 1
              fi
            '';
          };
        };

      # Panic-reboot fallback (D22). Auto-reboot 20 s after a kernel panic returns this
      # machine, which cannot be power-cycled or rebooted remotely, to the stage-1 unlock
      # prompt instead of leaving it dark. The panic-on-hang knobs (kernel.hung_task_panic,
      # softlockup_panic, hardlockup_panic) are deliberately NOT permanent: they
      # false-positive on ZFS scrubs and long nix builds and would spuriously reboot a daily
      # driver. Enable them only around a supervised suspend test, e.g.
      # `sysctl -w kernel.hung_task_panic=1 kernel.hung_task_timeout_secs=30`. efi_pstore
      # records the panic to EFI variables in the SPI boot ROM, surviving the dead NVMe that
      # erases the journal; systemd-pstore.service is wantedBy sysinit.target by default, so
      # the archive path needs no config here. mem_sleep_default is deliberately left
      # unpinned: s2idle was tested and also hung, so the failure is storage, not
      # sleep-state selection.
      boot.kernel.sysctl."kernel.panic" = 20;

      # Local GNOME desktop under GDM (D19), the two lines nixpkgs seeds into
      # nixos-generate-config. They are system-level and self-contained: they cascade
      # the display manager, XDG portals, the graphical polkit agent, gnome-keyring,
      # dconf, gnome-settings-daemon, gnome-control-center, the NetworkManager applet,
      # and gnome-shell, and a stock GNOME session needs nothing from cameron's
      # home-manager. GDM is a stage-2 display manager ordered after the root mount, so
      # it does not touch the initrd passphrase path, and it enables no plymouth
      # (2.9/D11 stand). niri is out of scope, deferred to a reversible follow-up.
      services.displayManager.gdm.enable = true;
      services.desktopManager.gnome.enable = true;

      # Bridge NixOS-level sops to home-manager for user secret key delivery.
      # sopsIdentity defaults to flake.users.cameron.meta.sopsAgeKeyId
      # ("crs58" via alias-fold inheritance).
      hm-sops-bridge.users.cameron = { };

      # cameron is the preferred username on new machines and folds to crs58 by alias;
      # alias-keyed reads keep this call site ignorant of the alias->target relationship.
      # Infrastructure settings (useGlobalPkgs, extraSpecialArgs, etc.) are provided by
      # the cameron inventory service.
      home-manager.users.cameron = {
        imports = flakeUsers.cameron.modules;
      };
    };
}
