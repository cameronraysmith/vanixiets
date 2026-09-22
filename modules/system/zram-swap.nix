{
  # Flake-parts module exporting to base namespace (merged with other base modules)
  flake.modules.nixos.base = {
    # Compressed in-memory swap: no disk I/O, no ZFS deadlock risk, and 4.2-4.5x
    # measured compression on nix-eval workloads, so its real RAM cost is a
    # fraction of its capacity. Capacity is not a resident-memory bound: pages
    # move here only under reclaim pressure, and systemd-oomd counts swap usage
    # against the total. Per-machine overrides raise the percentage where both
    # of those are accounted for.
    zramSwap.enable = true;
    zramSwap.memoryPercent = 100;
  };
}
