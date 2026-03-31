{
  # Ensure home-manager services wait for ZFS mounts to complete
  # Auto-merges into base namespace
  #
  # Without this, a race condition on cloud VMs causes /home to briefly
  # fail to mount (ZFS pool import is slow), which cascades to the
  # home-manager service failing with "Dependency failed".
  flake.modules.nixos.base =
    { config, lib, ... }:
    {
      systemd.services = lib.mkIf config.boot.zfs.enabled (
        lib.mapAttrs' (
          username: _:
          lib.nameValuePair "home-manager-${username}" {
            after = [ "zfs.target" ];
            wants = [ "zfs.target" ];
          }
        ) (config.home-manager.users or { })
      );
    };
}
