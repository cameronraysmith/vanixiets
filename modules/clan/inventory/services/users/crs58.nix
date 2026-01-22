# Admin user for legacy machines (forced username)
# Clan users service settings apply to NixOS only; extraModules work cross-platform
{
  inputs,
  ...
}:
{
  clan.inventory.instances.user-crs58 = {
    module = {
      name = "users";
      input = "clan-core";
    };

    # Machine-specific targeting (legacy machines)
    roles.default.machines."stibnite" = { };
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
          # Home-Manager infrastructure settings only
          # Module imports are defined at machine level (blackphos, stibnite modules)
          # to avoid duplicate catppuccin imports when clan deploys
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
          };
        }
      )
    ];
  };
}
