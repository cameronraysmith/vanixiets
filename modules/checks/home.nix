# Home-manager activationPackage build-realization checks.
#
# Wires each homeConfigurations."<user>@<system>" activationPackage as a flake
# check, closing the silently-no-op build gap reported in bead nix-144.4. The
# activationPackage is the already-built derivation that `home-manager switch`
# activates, so binding it as a check following ironstar's package-as-check
# idiom (modules/rust.nix:249-251) exercises the full home closure per system.
#
# Standalone homes are checked against one archetype per platform, not every
# `homeConfigurations` entry. A user is kept for a system when either:
#   (a) it is the canonical user (crs58), covering the standalone
#       `homeConfigurations` / mk-home path itself on that platform; or
#   (b) its home is NOT already evaluated inside some nixosConfiguration /
#       darwinConfiguration of that same system (host-embedded homes compose
#       the same `flake.users.<u>.modules` recipe and are checked via the
#       machine configurations).
# Aliases (`flake.userAliases`, e.g. cameron -> crs58) are dropped: they copy
# the target's aggregates/systems/contentPrivate and differ only in
# `home.username`/`home.homeDirectory`.
#
# Host coverage evidence (`.#.{nixos,darwin}Configurations.<m>.config.home-manager.users`,
# 2026-10-06):
#   x86_64-linux:   cinnabar/electrum [cameron]; galena/scheelite [cameron tara];
#                   magnetite/pyrite [cameron omnigent-cameron omnigent-janettesmith]
#   aarch64-darwin: argentum [cameron christophersmith]; blackphos [crs58 raquel];
#                   rosegold [cameron janettesmith]; stibnite [crs58]
# Hence: x86_64-linux drops tara (galena, scheelite) and cameron (alias);
# aarch64-darwin drops christophersmith (argentum), raquel (blackphos),
# janettesmith (rosegold) and cameron (alias). Revisit this list when host
# user assignments or `flake.users` change.
#
# The key set is a literal per system so computing `checks.<system>` names
# never forces `flake.users` aggregates, machine configurations, or `pkgs`.
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
  ...
}:
let
  checkedUsers = {
    x86_64-linux = [
      "crs58"
      "christophersmith"
      "janettesmith"
      "raquel"
      "ubuntu"
    ];
    aarch64-darwin = [
      "crs58"
      "tara"
    ];
  };
in
{
  perSystem =
    { system, ... }:
    {
      checks = lib.listToAttrs (
        map (user: {
          name = "home-manager-${user}";
          value = self.homeConfigurations."${user}@${system}".activationPackage;
        }) (checkedUsers.${system} or [ ])
      );
    };
}
