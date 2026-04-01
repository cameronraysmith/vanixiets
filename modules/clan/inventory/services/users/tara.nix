# External ML researcher on GPU/CPU cloud nodes
{
  inputs,
  ...
}:
{
  clan.inventory.instances.user-tara = {
    module = {
      name = "users";
      input = "clan-core";
    };

    # GPU and CPU cloud nodes only
    roles.default.machines."scheelite" = { };
    roles.default.machines."galena" = { };

    roles.default.settings = {
      user = "tara";
      groups = [
        "video" # GPU device access
        "render" # GPU render node access
      ];
      share = true;
      prompt = false;
    };

    roles.default.extraModules = [
      (
        {
          pkgs,
          ...
        }:
        {
          users.users.tara.shell = pkgs.zsh;

          users.users.tara.openssh.authorizedKeys.keys = inputs.self.lib.userIdentities.tara.sshKeys;

          programs.zsh.enable = true;

          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            backupFileExtension = "before-home-manager";

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
