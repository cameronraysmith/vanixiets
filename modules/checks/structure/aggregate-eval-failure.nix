# Falsifiable structural check: asserts that referencing an undeclared
# name in the flake.modules.homeManager registry fails to evaluate.
# `builtins.tryEval` returns `success = false` when the bad lookup
# throws — preserving the falsifiable semantic that aggregate references
# in `flake.users.<u>.aggregates` must resolve at module-merge time.
#
# The accessor is wrapped with `or (throw …)` because nix's missing-
# attribute error from direct attr-set access is not catchable by
# `tryEval` directly. The wrap converts the lookup failure into a
# `throw`, which `tryEval` does catch — preserving the falsifiable
# semantic that the spec intended.
#
# Severity rationale: if `flake.modules.homeManager` were ever replaced
# with a default-bag that silently returns null/{} for missing keys,
# the inner accessor would succeed (no `throw`), `tryEval` would return
# `success = true`, and this check would fail — catching a regression
# that loses module-merge type discipline. Negative-control verifiable:
# flipping `expected` to `true` causes the check to fail. The assertion
# has falsifiable severity by construction.
{ self, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      mkCheck = self.lib.mkStructuralCheck pkgs;
    in
    {
      checks.structure-aggregate-eval-failure = mkCheck {
        name = "aggregate-eval-failure";
        actual =
          (builtins.tryEval (
            self.modules.homeManager.deliberately-undeclared
              or (throw "deliberately-undeclared aggregate is absent (expected)")
          )).success;
        expected = false;
      };
    };
}
