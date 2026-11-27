# Admin user for modern machines (preferred username)
# Clan users service settings apply to NixOS only; extraModules work cross-platform
{
  config,
  inputs,
  lib,
  ...
}:
{
  flake.clan.inventory.instances.user-cameron = {
    module = {
      name = "users";
      input = "clan-core";
    };

    # Every host with a cameron attachment (modules/lib/host-users.nix)
    roles.default.machines = lib.genAttrs (config.flake.lib.hostsOfAccount "cameron") (_: { });

    roles.default.settings = {
      user = "cameron";
      groups = [
        "wheel" # sudo access
        "networkmanager" # network configuration
      ];
      share = true; # Same password across all admin users (nixos only currently)
      prompt = false; # Auto-generate password via xkcdpass (nixos only currently)
    };

    # User overlay: shell and SSH keys. The home-manager integration and the
    # home itself come from the host's attachment
    # (modules/system/home-manager-integration.nix).
    roles.default.extraModules = [
      (
        {
          lib,
          pkgs,
          ...
        }:
        {
          users.users.cameron = lib.mkMerge [
            {
              # Shell preference (works on both platforms)
              shell = pkgs.zsh;

              openssh.authorizedKeys.keys = inputs.self.users.cameron.meta.sshKeys;
            }

            # NixOS-only option, so optionalAttrs keeps the attribute path from
            # existing at all on darwin. Without lingering the user manager
            # stops with the last login session and takes every user unit with
            # it, while session-scope processes survive under
            # KillUserProcesses=false: unattended work keeps running on a host
            # whose per-user daemons have already exited.
            (lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
              linger = true;
            })
          ];
          # Enable zsh system-wide (works on both platforms)
          programs.zsh.enable = true;
        }
      )
    ];
  };
}
