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
# Derived, not hardcoded: any NixOS machine whose services.zerotierone.package
# diverges from its own pkgs.zerotierone is by definition building a variant
# cache.nixos.org cannot hold, so it gets a check.
{ self, lib, ... }:
{
  perSystem =
    { system, ... }:
    let
      machineSystems = self.lib.machineSystems;

      onThisSystem = lib.filterAttrs (name: _: machineSystems.${name} == system) self.nixosConfigurations;

      divergent = lib.filterAttrs (
        _: machine:
        machine.config.services.zerotierone.enable
        && machine.config.services.zerotierone.package.drvPath != machine.pkgs.zerotierone.drvPath
      ) onThisSystem;
    in
    {
      checks = lib.mapAttrs' (
        name: machine:
        lib.nameValuePair "zerotierone-controller-${name}" machine.config.services.zerotierone.package
      ) divergent;
    };
}
