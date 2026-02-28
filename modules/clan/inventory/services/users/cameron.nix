# Admin user for modern machines (preferred username)
# Clan users service settings apply to NixOS only; extraModules work cross-platform
{
  inputs,
  ...
}:
{
  clan.inventory.instances.user-cameron = {
    module = {
      name = "users";
      input = "clan-core";
    };

    # Machine-specific targeting (modern machines)
    roles.default.machines."cinnabar" = { };
    roles.default.machines."electrum" = { };
    roles.default.machines."argentum" = { };
    roles.default.machines."rosegold" = { };
    roles.default.machines."galena" = { };
    roles.default.machines."scheelite" = { };

    roles.default.settings = {
      user = "cameron";
      groups = [
        "wheel" # sudo access
        "networkmanager" # network configuration
      ];
      share = true; # Same password across all admin users (nixos only currently)
      prompt = false; # Auto-generate password via xkcdpass (nixos only currently)
    };

    # User overlay: shell, SSH keys, home-manager configuration
    # Home-manager module is imported at machine level (nixos/darwin specific)
    # This extraModule only provides configuration
    roles.default.extraModules = [
      (
        {
          pkgs,
          ...
        }:
        {
          # Shell preference (works on both platforms)
          users.users.cameron.shell = pkgs.zsh;

          users.users.cameron.openssh.authorizedKeys.keys = inputs.self.lib.userIdentities.crs58.sshKeys;

          # Enable zsh system-wide (works on both platforms)
          programs.zsh.enable = true;

          # Home-Manager infrastructure settings only
          # Module imports are defined at machine level (argentum, rosegold, etc.)
          # to avoid duplicate catppuccin imports when clan deploys
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            # Backup conflicting files instead of failing (prevents race condition on GCP)
            backupFileExtension = "before-home-manager";

            # Pass flake as extraSpecialArgs for sops-nix access
            # Bridge from outer inputs to home-manager modules
            extraSpecialArgs = {
              flake = inputs.self // {
                inherit inputs;
              };
            };
          };
        }
      )
    ];
  };
}
