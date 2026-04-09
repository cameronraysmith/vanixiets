{
  # Flake-parts module exporting to base namespace (merged with other base modules)
  flake.modules.nixos.base = {
    # Compressed in-memory swap (zram) for effective memory extension
    # Doubles effective memory via compression without disk I/O or ZFS deadlock risk
    zramSwap.enable = true;
    zramSwap.memoryPercent = 100;
  };
}
