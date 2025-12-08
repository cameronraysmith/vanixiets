{
  inputs,
  ...
}:
{
  # Admin user on legacy machines (crs58 username forced by existing setup)
  # Deployed to: blackphos (darwin, ready now)
  # Future: stibnite (darwin, when machine is configured)
  # User identity: SAME crs58 home module (same SSH keys, git config, packages)
  # Username: crs58 (forced on legacy machines)
  #
  # Note: Clan users service is currently NixOS-only. On darwin machines:
  #   - settings.* (user, groups, share, prompt) are ignored
  #   - extraModules provide all user configuration (works cross-platform)
  #   - vars-based password management unavailable (NixOS feature)
  # This pattern is forward-compatible with future darwin support.
  clan.inventory.instances.user-crs58 = {
    module = {
      name = "users";
      input = "clan-core";
    };

    # Machine-specific targeting (legacy machines)
    # roles.default.machines."stibnite" = { };  # Uncomment when stibnite is configured
    roles.default.machines."blackphos" = { };

    roles.default.settings = {
      user = "crs58";
      groups = [
        "wheel" # sudo access
        "networkmanager" # network configuration
      ];
      share = true; # Same password as cameron instances (nixos only currently)
      prompt = false; # Auto-generate password via xkcdpass (nixos only currently)
    };

    # User overlay: IDENTICAL to cameron, just different username
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
          users.users.crs58.shell = pkgs.zsh;

          # SSH authorized keys (works on both platforms)
          users.users.crs58.openssh.authorizedKeys.keys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdO9rInDa9HvdtZZxmkgeEdAlTupCy3BgA/sqSGyUH+"
          ];

          # Enable zsh system-wide (works on both platforms)
          programs.zsh.enable = true;

          # Home-Manager: Import SAME crs58 identity module, keep username=crs58
          # Note: home.homeDirectory is automatically set by crs58 module's conditional:
          #   - /home/crs58 on Linux (if any)
          #   - /Users/crs58 on Darwin (blackphos, stibnite)
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            # Backup conflicting files instead of failing (prevents race condition on cloud VMs)
            backupFileExtension = "before-home-manager";

            # Pass flake as extraSpecialArgs for sops-nix access
            # Bridge from outer inputs to home-manager modules
            extraSpecialArgs = {
              flake = inputs.self // {
                inherit inputs;
              };
            };

            users.crs58 = {
              imports = [
                inputs.self.modules.homeManager."users/crs58"
                inputs.self.modules.homeManager.base-sops
                # Import aggregate modules for crs58
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
              home.username = "crs58";
            };
          };
        }
      )
    ];
  };
}
