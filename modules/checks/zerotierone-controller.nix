# Warm the ZeroTier controller's unfree zerotierone build in the fleet cache
#
# clan-core builds the controller's daemon differently from every peer's:
# clanServices/zerotier/pkgs/zerotierone/default.nix takes
# `zerotierone.override { enableUnfree = true; }` whenever the controller role
# is active and the version is >= 1.16, which adds ZT_NONFREE=1 and flips the
# license to unfree. That is a distinct derivation, and cache.nixos.org never
# carries it because Hydra builds only the free default. Measured on the
# current lock: the peer output is a 200 on cache.nixos.org, the controller
# output a 404.
#
# The consequence is that exactly one machine in the fleet — the controller —
# has a permanent, structural cache miss for zerotierone unless something in
# our own CI builds that derivation and pushes it to
# cache.scientistexperience.net. `clan machines update` defaults its build host
# to the target host, so an unwarmed deploy compiles ZeroTier from source on
# the controller itself.
#
# The machine toplevel check (modules/checks/machines.nix) does cover it, but
# only as a byproduct of a large closure: any unrelated failure in that closure
# withholds the push. This check builds the one derivation on its own, so the
# push is independent of the rest of the machine and costs nothing once cached.
#
# Keyed by the zerotier instance's controller role in the clan inventory, so
# the check's name is static data. The divergence that motivates the check is
# asserted in the value: if clan stops overriding the controller's package,
# the check fails rather than silently warming the free build cache.nixos.org
# already carries.
{ self, lib, ... }:
{
  perSystem =
    { system, ... }:
    let
      machineSystems = self.lib.machineSystems;

      controllers = lib.filter (name: machineSystems.${name} == system) (
        builtins.attrNames self.clan.inventory.instances.zerotier.roles.controller.machines
      );

      controllerPackage =
        name:
        let
          machine = self.nixosConfigurations.${name};
          zerotierone = machine.config.services.zerotierone;
        in
        assert lib.assertMsg zerotierone.enable
          "zerotier controller ${name} does not enable services.zerotierone";
        assert lib.assertMsg (zerotierone.package.drvPath != machine.pkgs.zerotierone.drvPath)
          "zerotier controller ${name}'s services.zerotierone.package no longer diverges from pkgs.zerotierone; cache.nixos.org already carries it and this check is obsolete";
        zerotierone.package;
    in
    {
      checks = lib.listToAttrs (
        map (name: lib.nameValuePair "zerotierone-controller-${name}" (controllerPackage name)) controllers
      );
    };
}
