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
      userRecord = config.flake.users.${user};
      userMeta = userRecord.meta;
      aggs = userRecord.aggregates;

      effectiveUsername = if username == null then userMeta.username else username;
      effectiveHomeDirectory =
        if homeDirectory != null then
          homeDirectory
        else if (lib.hasInfix "darwin" system) then
          "/Users/${effectiveUsername}"
        else
          "/home/${effectiveUsername}";

      aggregateModules = aggs;
      contentModule = if includePrivate then userRecord.contentPrivate else userRecord.contentPortable;

      # Typed identity-override fragment synthesized for every user record
      # by identity-fold.nix; alias-fold extends it with mkForce setters.
      typedIdentityOverride = userRecord.identityOverride;

      # Legacy explicit-caller-arg branch retained for the
      # `mk-home { user = "..."; username = "..."; }` invocation shape.
      # Standalone homeConfigurations no longer use it (configurations.nix
      # post-A2* invokes `mk-home { user = name; system; }` for every
      # entry, including aliases). Remaining callers are explicit overrides
      # outside the standard alias path.
      legacyIdentityOverride = lib.optional (username != null || homeDirectory != null) {
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
        ++ [ typedIdentityOverride ]
        ++ legacyIdentityOverride
        ++ extraModules;
    };
}
