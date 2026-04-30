{
  config,
  inputs,
  lib,
  ...
}:
{
  flake.lib.mkHome =
    {
      user,
      includePrivate ? true,
      username ? null,
      homeDirectory ? null,
      system ? builtins.currentSystem,
      extraModules ? [ ],
    }:
    let
      userMeta = config.flake.users.${user}.meta;
      profiles = config.flake.users.${user}.profiles;

      effectiveUsername = if username == null then userMeta.username else username;
      effectiveHomeDirectory =
        if homeDirectory != null then
          homeDirectory
        else if (lib.hasInfix "darwin" system) then
          "/Users/${effectiveUsername}"
        else
          "/home/${effectiveUsername}";

      contentKey = if includePrivate then "users/${user}" else "portable/${user}";

      aggregateModules = lib.concatMap (p: p.includes) profiles;
      contentModule = config.flake.modules.homeManager.${contentKey};

      identityOverride = lib.optional (username != null || homeDirectory != null) {
        home.username = lib.mkForce effectiveUsername;
        home.homeDirectory = lib.mkForce effectiveHomeDirectory;
      };
    in
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [
          config.flake.overlays.default
        ];
      };
      extraSpecialArgs = {
        flake = config.flake // {
          inherit inputs;
        };
      };
      modules =
        aggregateModules
        ++ [ contentModule ]
        ++ lib.optional includePrivate config.flake.modules.homeManager.base-sops
        ++ [ inputs.lazyvim-nix.homeManagerModules.default ]
        ++ identityOverride
        ++ extraModules;
    };
}
