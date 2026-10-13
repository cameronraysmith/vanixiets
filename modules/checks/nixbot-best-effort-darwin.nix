# nixbot builds checks.aarch64-darwin as best-effort.
#
# Those builds can only run on a Mac reachable from magnetite, and the Macs are
# laptops that sleep, travel, and are often unreachable
# (modules/clan/inventory/services/nix-builders.nix). Every darwin check
# therefore carries hercules-ci's ignoreFailure modifier, which nixbot reads
# from each job (nixbot/nixbot/nix/apply.nix:6): a failed darwin attribute,
# or one whose failed dependency settled it, is reported as an ignored
# failure, excluded from the build's aggregate status, and kept out of the
# failed-build cache so the next build retries it (nixbot/build_scheduler.py
# `outcome_status`, `dependency_failed_status`, `_finish_job`). Once every
# other attribute has settled, a darwin attribute still unfinished after
# `optional_build_grace` (nixbot.toml) is stopped and ignored the same way
# (`JobScheduler._abandon_optional`), so a sleeping Mac never holds a build.
# The last two behaviours are local patches (modules/nixos/nixbot.nix).
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
