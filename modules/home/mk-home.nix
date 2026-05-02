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
      modules = config.flake.users.${user}.modules;
    };
}
