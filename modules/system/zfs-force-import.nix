{
  # Pin boot.zfs.forceImportRoot to silence the 26.11-default-change warning
  # without changing runtime behavior.
  #
  # Upstream nixpkgs flips the default from `true` to `false` at
  # stateVersion 26.11 to enforce ZFS's hostid-mismatch and unclean-export
  # interlocks during initrd `zpool import`. Those interlocks defend
  # exclusively against the dual-import data-loss class (two kernels
  # writing to the same pool concurrently), which is unreachable on our
  # local-disk Hetzner cloud VMs. Setting `false` would, however, block
  # boot after every unclean shutdown until someone opens the web console
  # and adds `zfs_force=1` to the kernel cmdline.
  #
  # Explicitly pinning to `true` preserves automatic recovery on the
  # always-on coordinator (cinnabar) and build infrastructure (magnetite)
  # while satisfying the warning's "set explicitly to silence" condition.
  # Revisit if/when shared block storage or volume re-attach workflows
  # enter the architecture.
  flake.modules.nixos.base = {
    boot.zfs.forceImportRoot = true;
  };
}
