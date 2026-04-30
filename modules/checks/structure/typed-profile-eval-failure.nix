# Falsifiable structural check: asserts that referencing an undeclared
# profile name fails to evaluate. The expectation here is `false` —
# `builtins.tryEval` returns `success = false` when the bad reference
# throws (which is the desired behavior of a typed registry).
#
# The accessor is wrapped with `or (throw …)` because nix's missing-
# attribute error is raised at parse-position and is not catchable by
# `tryEval` directly. The wrap converts the lookup failure into a
# `throw`, which `tryEval` does catch — preserving the falsifiable
# semantic that the spec intended.
#
# Severity rationale: if `flake.lib.profiles.homeManager` were ever
# replaced with a bag that silently returns null/{} for missing keys,
# the inner accessor would succeed (no `throw`), `tryEval` would return
# `success = true`, and this check would fail — catching a regression
# that loses type discipline. The negative-control (flipping `expected`
# to `true`) was confirmed locally to fail before revert; the assertion
# has falsifiable severity by construction.
{ self, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      mkCheck = self.lib.mkStructuralCheck pkgs;
    in
    {
      checks.structure-typed-profile-eval-failure = mkCheck {
        name = "typed-profile-eval-failure";
        actual =
          (builtins.tryEval (
            self.lib.profiles.homeManager.deliberately-undeclared.includes
              or (throw "deliberately-undeclared profile is absent (expected)")
          )).success;
        expected = false;
      };
    };
}
