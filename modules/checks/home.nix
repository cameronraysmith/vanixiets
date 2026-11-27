# Home-manager activationPackage build-realization checks.
#
# Wires each homeConfigurations."<user>@<system>" activationPackage as a flake
# check, closing the silently-no-op build gap reported in bead nix-144.4. The
# activationPackage is the already-built derivation that `home-manager switch`
# activates, so binding it as a check following ironstar's package-as-check
# idiom (modules/rust.nix:249-251) exercises the full home closure per system.
#
# Standalone homes are checked against one archetype per platform, not every
# `homeConfigurations` entry. For each of x86_64-linux and aarch64-darwin, a
# user is kept when either:
#   (a) it is the canonical user (crs58), covering the standalone
#       `homeConfigurations` / mk-home path itself on that platform; or
#   (b) it is a `flake.users` key that is not a `flake.userAliases` key,
#       whose `systems` include the system, and that no host of that system
#       attaches (`flake.fleet.hosts.<host>.users`, lib/host-users.nix):
#       host-embedded homes compose the same `flake.users.<u>.modules` recipe
#       and are checked via the machine configurations.
# Aliases (e.g. cameron -> crs58) are dropped: they copy the target's
# aggregates/systems/contentPrivate and differ only in
# `home.username`/`home.homeDirectory`. aarch64-linux gets no home check.
#
# claude-sandbox is embedded in no host; its check is also what makes nixbot
# build the activation package and niks3 publish it to
# cache.scientistexperience.net, from which Claude Code cloud sessions
# substitute it (modules/apps/claude-sandbox-setup.sh).
#
# The key set reads only attachment names, `flake.users` names, aliases and
# each user's `systems`, so computing `checks.<system>` names never forces
# `flake.users` aggregates, machine configurations, or `pkgs`.
#
# Binds the activationPackage directly (no overrideAttrs wrapper). A prior
# revision wrapped it with overrideAttrs to add a cosmetic meta.description,
# which changed the derivation hash and broke drvPath equality with what
# `home-manager switch` actually evaluates: the check built one drv, activation
# built another, and CI cache fills could not serve activation back.
#
# Closes: nix-144.4
{
  config,
  self,
  lib,
  ...
}:
let
  inherit (config.flake) users userAliases;
  inherit (config.flake.lib) hosts machineSystems;
  attachedOn =
    system: user:
    lib.any (host: machineSystems.${host} == system && hosts.${host}.users ? ${user}) (
      lib.attrNames machineSystems
    );
  checkedUsers = lib.genAttrs [ "x86_64-linux" "aarch64-darwin" ] (
    system:
    [ "crs58" ]
    ++ lib.filter (
      user:
      user != "crs58"
      && !(userAliases ? ${user})
      && lib.elem system users.${user}.systems
      && !(attachedOn system user)
    ) (lib.attrNames users)
  );
in
{
  perSystem =
    { system, ... }:
    {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks =
        {
          x86_64-linux = {
            # nixbot: median 7.1 s, slowest 2019 s, 685 runs in 30 days
            home-manager-christophersmith.class = "small";
            # nixbot: median 18 s, slowest 56 s, 20 runs in 30 days
            home-manager-claude-sandbox.class = "small";
            # nixbot: median 17 s, slowest 2018 s, 701 runs in 30 days
            home-manager-crs58.class = "small";
            # nixbot: median 7.2 s, slowest 2010 s, 686 runs in 30 days
            home-manager-janettesmith.class = "small";
            # nixbot: median 7.2 s, slowest 1994 s, 686 runs in 30 days
            home-manager-raquel.class = "small";
            # nixbot: median 6.4 s, slowest 2466 s, 683 runs in 30 days
            home-manager-ubuntu.class = "small";
          };
          aarch64-darwin = {
            # nixbot: median 93 s, slowest 533 s, 573 runs in 30 days
            home-manager-crs58.class = "medium";
            # nixbot: median 42 s, slowest 434 s, 572 runs in 30 days
            home-manager-tara.class = "small";
          };
        }
        .${system} or { };
      checks = lib.listToAttrs (
        map (user: {
          name = "home-manager-${user}";
          value = self.homeConfigurations."${user}@${system}".activationPackage;
        }) (checkedUsers.${system} or [ ])
      );
    };
}
