{
  config,
  inputs,
  ...
}:
{
  flake.lib.mkHome =
    {
      user,
      system ? builtins.currentSystem,
    }:
    let
      userRecord = config.flake.users.${user};
      aggregateModules = userRecord.aggregates;
      contentModule = userRecord.contentPrivate;

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
      modules = aggregateModules ++ [ contentModule ] ++ [ identity ];
    };
}
