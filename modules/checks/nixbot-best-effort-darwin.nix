# nixbot builds checks.aarch64-darwin as best-effort.
#
# Those builds can only run on a Mac reachable from magnetite, and the Macs are
# laptops that sleep, travel, and refuse builds on battery
# (modules/clan/inventory/services/nix-builders.nix). Every darwin check
# therefore carries hercules-ci's ignoreFailure modifier, which nixbot reads
# from each job (nixbot/nixbot/nix/apply.nix:6): a failed darwin attribute is
# reported as an ignored failure, excluded from the build's aggregate status,
# and kept out of the failed-build cache so the next build retries it
# (nixbot/nixbot/build_scheduler.py:119-121, 286, 447).
#
# The cost of that is real: nixbot cannot tell an absent builder from a
# genuine darwin regression, so a broken darwin check is a notice in CI too.
# Local `just check-fast` on a Mac stays the gate for darwin.
#
# Adding an attribute to a derivation's attribute set changes neither its
# drvPath nor its outputs, so nothing rebuilds and binary caches still apply;
# `nix flake check` ignores the attribute. A darwin evaluation error is not
# covered: it fails the build before the modifier is read, which is correct
# for an error no builder could have caused.
{ config, lib, ... }:
{
  flake.checks.aarch64-darwin = lib.mkForce (
    lib.mapAttrs (_: check: check // { ignoreFailure = true; }) config.allSystems.aarch64-darwin.checks
  );
}
