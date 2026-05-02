# Falsifiable structural check for the per-user assertion clause in
# `flake.modules.nixos.hm-sops-bridge` (see modules/nixos/hm-sops-bridge.nix).
#
# The bridge module emits one assertion per `hm-sops-bridge.users.<u>` entry
# requiring `flake.users.<u>.meta.sopsAgeKeyId` to be non-null. The assertion
# is consumed by the NixOS module system at system-build time, but the
# assertions list is also reachable by a pure `lib.evalModules` invocation
# against the deferred module's closure — without instantiating an entire
# nixosConfiguration.
#
# This check exercises the assertion against a phantom user that is NOT
# present in `flake.users`, and verifies the resolved `assertion` predicate
# evaluates to `false` (i.e. the assertion correctly fires for the phantom).
# The phantom uses an explicit `sopsIdentity = "..."` to bypass the option's
# default-throw at lines 31-34 of the bridge module, which would otherwise
# short-circuit the eval before reaching the assertions clause.
#
# Severity rationale (Mayo): the check passes only when the assertion's
# predicate `(flakeUsers ? <u>) && (flakeUsers.<u>.meta.sopsAgeKeyId or null)
# != null` correctly classifies a phantom-user input as failing. Mutation:
# weakening the predicate to constant `true`, or to a tautology that ignores
# its inputs, flips `actual.phantomFires` to `true` and fails the JSON diff
# against `expected.phantomFires = false`. The check is severe in Mayo's
# sense — it would fail under plausible incorrect implementations of the
# bridge's per-user assertion clause.
#
# A symmetric positive control input (`crs58`, present in `flake.users` with
# a real `sopsAgeKeyId`) is included to verify the predicate also classifies
# valid inputs as passing, ruling out the "always-false" tautology.
{ self, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      lib = pkgs.lib;
      mkCheck = self.lib.mkStructuralCheck pkgs;

      # Evaluate the bridge module against a synthetic config that enables
      # one phantom user (not in `flake.users`) and one canonical user
      # (`crs58`, present with a valid sopsAgeKeyId), then return the
      # resolved assertions list keyed by username for inspection.
      evalBridge =
        userConfig:
        (lib.evalModules {
          modules = [
            self.modules.nixos.hm-sops-bridge
            {
              _module.check = false;
              freeformType = lib.types.lazyAttrsOf lib.types.raw;
            }
            { hm-sops-bridge.users = userConfig; }
          ];
        }).config.assertions;

      # Single-element assertions for clarity. Each evaluation produces
      # exactly one assertion (the per-user mapping in the bridge).
      phantomAssertions = evalBridge {
        # Not present in flake.users; explicit sopsIdentity bypasses the
        # option's default-throw so the assertion clause is reachable.
        phantomNoMeta.sopsIdentity = "explicit-bypass";
      };
      canonicalAssertions = evalBridge {
        # Present in flake.users with a real sopsAgeKeyId; sopsIdentity
        # default resolves cleanly via meta.sopsAgeKeyId.
        crs58 = { };
      };
    in
    {
      checks.hm-sops-bridge-assertion-neg = mkCheck {
        name = "hm-sops-bridge-assertion-neg";
        actual = {
          phantomFires = (lib.elemAt phantomAssertions 0).assertion;
          canonicalPasses = (lib.elemAt canonicalAssertions 0).assertion;
        };
        expected = {
          phantomFires = false;
          canonicalPasses = true;
        };
      };
    };
}
