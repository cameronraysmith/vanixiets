{
  config,
  inputs,
  withSystem,
  ...
}:
{
  flake.lib.mkHome =
    {
      user,
      system ? builtins.currentSystem,
    }:
    inputs.home-manager.lib.homeManagerConfiguration {
      # The per-system fleet instance from modules/nixpkgs/base-defaults.nix,
      # shared with every machine and home of the same system.
      pkgs = withSystem system ({ fleetPkgs, ... }: fleetPkgs);
      extraSpecialArgs = {
        flake = config.flake // {
          inherit inputs;
        };
        # home-manager's NixOS and nix-darwin modules pass the enclosing system
        # configuration under this name; a standalone home configuration has no
        # such system, and saying so explicitly is what keeps a module that
        # takes the argument evaluable here. An absent module argument is not
        # the same as one that is null: the module system binds every formal it
        # knows about, including optional ones, to a thunk that throws when the
        # name cannot be resolved, so the formal's own default never applies.
        osConfig = null;
      };
      modules = config.flake.users.${user}.modules;
    };
}
