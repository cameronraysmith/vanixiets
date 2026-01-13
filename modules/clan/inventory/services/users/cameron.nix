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

    # User overlay: shell, SSH keys, home-manager integration
    # Provides cross-platform user configuration (works on both nixos and darwin)
    roles.default.extraModules = [
      inputs.home-manager.nixosModules.home-manager # Cross-platform (adapts via common.nix)
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

          # Home-Manager: Import crs58 identity module with cameron username
          # Note: home.homeDirectory is automatically set by crs58 module's conditional:
          #   - /home/cameron on Linux (cinnabar, electrum)
          #   - /Users/cameron on Darwin (argentum, rosegold)
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

            users.cameron = {
              imports = [
                inputs.self.modules.homeManager."users/crs58"
                inputs.self.modules.homeManager.base-sops
                # Import aggregate modules for crs58/cameron
                # All aggregates (matches blackphos configuration)
                inputs.self.modules.homeManager.ai
                inputs.self.modules.homeManager.core
                inputs.self.modules.homeManager.development
                inputs.self.modules.homeManager.packages
                inputs.self.modules.homeManager.shell
                inputs.self.modules.homeManager.terminal
                inputs.self.modules.homeManager.tools
                # LazyVim home-manager module
                inputs.lazyvim-nix.homeManagerModules.default
                # nix-index-database for comma command-not-found (terminal aggregate)
                inputs.nix-index-database.homeModules.nix-index
                # agents-md option module (requires flake arg from extraSpecialArgs)
                ../../../../home/modules/_agents-md.nix
              ];
              home.username = "cameron";
            };
          };
        }
      )
    ];
  };
}
