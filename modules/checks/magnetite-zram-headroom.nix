{
  config,
  lib,
  ...
}:
let
  # The oracle is the invariant the number was chosen to satisfy, not a second
  # copy of the declaration: magnetite's compressed-swap capacity must exceed
  # the swap high-water mark measured for the `8 x 4096` nix-eval-jobs
  # configuration in logs/magnetite-zram-headroom-experiment.md §6.2.
  #
  # 33.68 GB (31.4 GiB) is run C1's peak `memory.swap.current`, the winning
  # configuration. Production swap before this change was a single zram0 at
  # 100 % of RAM, which is *below* that figure — that is precisely the
  # deployability blocker this machine's setting exists to clear, so the check
  # fails closed if the percentage is ever walked back.
  measuredPeakSwapBytes = 33680000000;

  # machines/magnetite/facter.json is generated on the metal by nixos-facter
  # and is not derived from any Nix option, so it is an independent source for
  # the RAM figure that `zramSwap.memoryPercent` is a percentage of. The
  # `phys_mem` resource (30.0 GiB) is slightly below the kernel's MemTotal
  # (30.6 GiB), so sizing against it is the conservative direction.
  facter = builtins.fromJSON (builtins.readFile ../../machines/magnetite/facter.json);
  memoryNodes = facter.hardware.memory;
  physMemResources = lib.concatMap (
    node: lib.filter (r: r.type == "phys_mem") node.resources
  ) memoryNodes;
  physMemBytes = lib.foldl' (total: r: total + r.range) 0 physMemResources;

  # modules/system/zram-swap.nix exports into the `base` namespace, i.e. every
  # machine. pyrite is a 15 GiB laptop that livelocked under zram pressure on
  # 2026-09-22 (no OOM kill, no userspace recovery, manual reboot), so raising
  # the fleet default would put more compressed data in RAM on exactly the
  # machine with the worst demonstrated failure mode. The headroom is therefore
  # magnetite-scoped, and this number is what keeps it that way.
  fleetDefaultPercent = 100;

  # The kernel default. magnetite must sit above it: zram swap is cheap enough
  # (4.55x measured compression, no disk I/O) that the reclaim policy tuned for
  # spinning media is the wrong trade here.
  kernelDefaultSwappiness = 60;

  gib = n: toString (n / 1024 / 1024 / 1024);
in
{
  perSystem =
    { system, ... }:
    lib.mkIf (system == "x86_64-linux") {
      checks.magnetite-zram-headroom =
        let
          machine = config.flake.nixosConfigurations.magnetite;
          cfg = machine.config;
          pkgs = machine.pkgs;

          percent = cfg.zramSwap.memoryPercent;
          capacityBytes = physMemBytes * percent / 100;
          swappiness = cfg.boot.kernel.sysctl."vm.swappiness" or null;

          others = lib.filterAttrs (name: _: name != "magnetite") config.flake.nixosConfigurations;
          otherPercents = lib.mapAttrs (_: m: m.config.zramSwap.memoryPercent) others;
          widened = lib.filterAttrs (_: p: p != fleetDefaultPercent) otherPercents;
          otherSwappiness = lib.filterAttrs (_: m: m.config.boot.kernel.sysctl ? "vm.swappiness") others;
        in
        assert lib.assertMsg (builtins.length physMemResources == 1 && physMemBytes > 0)
          "magnetite zram headroom: machines/magnetite/facter.json must report exactly one phys_mem resource with a positive range; any other shape means hardware.memory no longer means what this check reads it to mean. Re-run nixos-facter before trusting the capacity bound";
        assert lib.assertMsg (cfg.zramSwap.enable)
          "magnetite zram headroom: zramSwap must stay enabled on magnetite; it is the only swap device this host has";
        assert lib.assertMsg (capacityBytes >= measuredPeakSwapBytes) ''
          magnetite zram headroom: zramSwap.memoryPercent = ${toString percent} gives
          ${gib capacityBytes} GiB of swap against ${gib physMemBytes} GiB of RAM, below the
          ${gib measuredPeakSwapBytes} GiB peak that `8 x 4096` nix-eval-jobs reached in
          logs/magnetite-zram-headroom-experiment.md §6.2. Exhausting swap under that
          configuration OOM-kills inside the eval cgroup, and for nixbot an eval OOM is a
          permanent pull-request failure with no retry. Re-measure before lowering this.
        '';
        assert lib.assertMsg (swappiness != null && swappiness > kernelDefaultSwappiness) ''
          magnetite zram headroom: boot.kernel.sysctl."vm.swappiness" is ${
            if swappiness == null then
              "unset (kernel default ${toString kernelDefaultSwappiness})"
            else
              toString swappiness
          }.
          Capacity alone does not move pages: the resident footprint only falls into zram if the
          kernel is willing to swap, and the measured configuration ran at 100.
        '';
        assert lib.assertMsg (widened == { }) ''
          magnetite zram headroom: zramSwap.memoryPercent must stay at ${toString fleetDefaultPercent} on every
          other machine, but ${
            lib.concatStringsSep ", " (lib.mapAttrsToList (n: p: "${n} = ${toString p}") widened)
          }.
          The headroom is magnetite-scoped on purpose. pyrite is a 15 GiB laptop that livelocked
          under zram pressure on 2026-09-22 — the kernel OOM killer never fired and recovery needed
          a manual reboot — so raising the base default moves more compressed data into RAM on the
          machine with the worst demonstrated failure mode.
        '';
        assert lib.assertMsg (otherSwappiness == { }) ''
          magnetite zram headroom: boot.kernel.sysctl."vm.swappiness" must stay unset outside
          magnetite, but it is set on ${lib.concatStringsSep ", " (lib.attrNames otherSwappiness)}.
          A higher swappiness is only safe where swap capacity was raised to absorb the result.
        '';
        pkgs.runCommand "magnetite-zram-headroom"
          {
            passthru.meta.description = "magnetite's zram swap capacity covers the measured 8x4096 nix-eval-jobs peak, and the fleet default stays where it was";
          }
          ''
            mkdir -p "$out"
            cat > "$out/headroom" <<EOF
            facter-phys-mem-bytes=${toString physMemBytes}
            memory-percent=${toString percent}
            swap-capacity-bytes=${toString capacityBytes}
            measured-peak-swap-bytes=${toString measuredPeakSwapBytes}
            swappiness=${toString swappiness}
            fleet-default-percent=${toString fleetDefaultPercent}
            other-machines=${lib.concatStringsSep "," (lib.attrNames otherPercents)}
            EOF
            cat "$out/headroom"
          '';
    };
}
