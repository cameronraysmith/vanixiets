{
  config,
  inputs,
  ...
}:
{
  flake.lib.mkHome =
    {
      user,
      includePrivate ? true,
      system ? builtins.currentSystem,
      extraModules ? [ ],
    }:
    let
      userRecord = config.flake.users.${user};
      aggregateModules = userRecord.aggregates;
      contentModule = if includePrivate then userRecord.contentPrivate else userRecord.contentPortable;

      identity = userRecord.identity;
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
      modules = aggregateModules ++ [ contentModule ] ++ [ identity ] ++ extraModules;
    };
}
