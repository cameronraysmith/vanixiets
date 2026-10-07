# Weekly cleanup of stale gcroots, temproots, and broken gcroot symlinks.
# Stale automatic gcroots (result symlinks from abandoned checkouts) pin store paths indefinitely,
# so the garbage collector alone cannot reclaim them.
# The "-" ExecStart prefix ignores a non-zero exit, so one failing find does not skip the rest.
{
  flake.modules.nixos.base =
    { pkgs, ... }:
    {
      systemd.timers.nix-cleanup-gcroots = {
        timerConfig = {
          OnCalendar = [ "weekly" ];
          Persistent = true;
        };
        wantedBy = [ "timers.target" ];
      };

      systemd.services.nix-cleanup-gcroots = {
        serviceConfig = {
          Type = "oneshot";
          ExecStart = [
            # delete automatic gcroots older than 30 days
            "-${pkgs.findutils}/bin/find /nix/var/nix/gcroots/auto /nix/var/nix/gcroots/per-user -type l -mtime +30 -delete"
            # created by nix-collect-garbage, might be stale
            "-${pkgs.findutils}/bin/find /nix/var/nix/temproots -type f -mtime +10 -delete"
            # delete broken symlinks
            "-${pkgs.findutils}/bin/find /nix/var/nix/gcroots -xtype l -delete"
          ];
        };
      };
    };
}
