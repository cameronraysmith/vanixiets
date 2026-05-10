# Home-manager activationPackage build-realization checks.
#
# Wires each homeConfigurations."<user>@<system>" activationPackage as a flake
# check, closing the silently-no-op build gap reported in bead nix-144.4. The
# activationPackage is the already-built derivation that `home-manager switch`
# activates, so binding it as a check following ironstar's package-as-check
# idiom (modules/rust.nix:249-251) exercises the full home closure per system.
#
# Iterates every user emitted into `homeConfigurations` for the current system
# — including aliases (e.g. cameron) materialized by `aliases-fold.nix` — by
# filtering `flake.users` to those with non-empty `aggregates`. Single source
# of truth: drift between `configurations.nix`'s emission rule and this check
# set is impossible.
#
# Binds the activationPackage directly (no overrideAttrs wrapper). A prior
# revision wrapped it with overrideAttrs to add a cosmetic meta.description,
# which changed the derivation hash and broke drvPath equality with what
# `home-manager switch` actually evaluates: the check built one drv, activation
# built another, and CI cache fills could not serve activation back.
#
# Closes: nix-144.4
{
  self,
  lib,
  config,
  ...
}:
{
  perSystem =
    { system, ... }:
    let
      enumerableUsers = lib.attrNames (lib.filterAttrs (_: u: u.aggregates != [ ]) config.flake.users);
    in
    {
      checks = lib.listToAttrs (
        map (user: {
          name = "home-manager-${user}";
          value = self.homeConfigurations."${user}@${system}".activationPackage;
        }) enumerableUsers
      );
    };
}
