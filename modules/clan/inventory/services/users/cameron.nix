{
  inputs,
  ...
}:
{
  # Admin user on modern machines (cameron username preference)
  # Deployed to: cinnabar, electrum (nixos, ready now)
  # Future: argentum, rosegold (darwin, when machines are configured)
  # User identity: crs58 home module (SSH keys, git config, packages)
  # Username: cameron (preferred for new machines per CLAUDE.md)
  #
  # Note: Clan users service is currently NixOS-only. On darwin machines:
  #   - settings.* (user, groups, share, prompt) are ignored
  #   - extraModules provide all user configuration (works cross-platform)
  #   - vars-based password management unavailable (NixOS feature)
  # This pattern is forward-compatible with future darwin support.
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

          # SSH authorized keys (works on both platforms)
          users.users.cameron.openssh.authorizedKeys.keys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdO9rInDa9HvdtZZxmkgeEdAlTupCy3BgA/sqSGyUH+"
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFXI36PvOzvuJQKVXWbfQE7Mdb6avTKU1+rV1kgy8tvp pixel7-termux"
          ];

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
