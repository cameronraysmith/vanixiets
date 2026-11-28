# Admin user for modern machines (preferred username). The clan users
# service's settings apply to NixOS only; its extraModules work on both
# classes. The home-manager integration and the home itself come from the
# host's attachment (modules/system/home-manager-integration.nix).
{ config, ... }:
{
  flake.clan.inventory.instances.user-cameron = config.flake.lib.mkUserInstance {
    user = "cameron";
    groups = [
      "wheel" # sudo access
      "networkmanager" # network configuration
    ];
    shellAndKeys = true;
    extraModules = [
      (
        { lib, pkgs, ... }:
        {
          # NixOS-only option, so optionalAttrs keeps the attribute path from
          # existing at all on darwin. Without lingering the user manager
          # stops with the last login session and takes every user unit with
          # it, while session-scope processes survive under
          # KillUserProcesses=false: unattended work keeps running on a host
          # whose per-user daemons have already exited.
          users.users.cameron = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
            linger = true;
          };
        }
      )
    ];
  };
}
