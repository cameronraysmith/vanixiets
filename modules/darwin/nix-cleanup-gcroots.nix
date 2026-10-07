# Weekly cleanup of stale gcroots, temproots, and broken gcroot symlinks.
# Stale automatic gcroots (result symlinks from abandoned checkouts) pin store paths indefinitely,
# so the garbage collector alone cannot reclaim them.
# The launchd environment has a minimal PATH, so find is referenced by store path.
{
  flake.modules.darwin.base =
    { pkgs, ... }:
    {
      launchd.daemons.nix-cleanup-gcroots = {
        script = ''
          set -eu
          # delete automatic gcroots older than 30 days
          ${pkgs.findutils}/bin/find /nix/var/nix/gcroots/auto /nix/var/nix/gcroots/per-user -type l -mtime +30 -delete || true
          # created by nix-collect-garbage, might be stale
          ${pkgs.findutils}/bin/find /nix/var/nix/temproots -type f -mtime +10 -delete || true
          # delete broken symlinks
          ${pkgs.findutils}/bin/find /nix/var/nix/gcroots -xtype l -delete || true
        '';
        serviceConfig.StartCalendarInterval = [
          {
            Weekday = 0; # Sunday
            Hour = 3;
            Minute = 30;
          }
        ];
      };
    };
}
