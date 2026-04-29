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
          name = "vanixiets-home-${user}";
          value = (self.homeConfigurations."${user}@${system}".activationPackage).overrideAttrs (old: {
            meta = (old.meta or { }) // {
              description = "Build ${user}'s home-manager activation package for ${system}";
            };
          });
        }) enumerableUsers
      );
    };
}
