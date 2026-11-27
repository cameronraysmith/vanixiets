# judgeCases and mkJudgeCheck: the one form of a judge-over-fixtures check
# (register-fleet-obligations design D3). Each case carries the number of
# problems its judge must find; a case may carry its own `judge`, overriding
# the default, so a file with two judges passes one case set. `assertions`
# holds the invariants that are not cases. When every case gives its count
# and every assertion holds, the derivation is returned unchanged (an
# assertion leaves its body's derivation as it is), so a check's drvPath does
# not depend on this wiring. Otherwise evaluation fails with one line per
# wrong case, naming the expected and the actual count and the judge's
# messages, followed by each failing assertion's message.
# Neither function reads or emits a testSizes entry: each check keeps its
# literal entry beside its definition (declare-test-size-classes design D1).
{ lib, ... }:
let
  judgeCases =
    {
      name,
      judge,
      cases,
      assertions ? [ ],
    }:
    drv:
    let
      judged = lib.mapAttrs (
        _: case:
        let
          messages = (case.judge or judge) case;
        in
        {
          expected = case.problems;
          inherit messages;
          got = lib.length messages;
        }
      ) cases;
      wrong = lib.filterAttrs (_: r: r.got != r.expected) judged;
      lines =
        lib.mapAttrsToList (
          case: r:
          "${name}: ${case}: expected ${toString r.expected} problems, the judge gave ${toString r.got}: ${builtins.toJSON r.messages}"
        ) wrong
        ++ map (a: "${name}: ${a.message}") (lib.filter (a: !a.assertion) assertions);
    in
    assert lib.assertMsg (lines == [ ]) (lib.concatStringsSep "\n" lines);
    drv;
in
{
  flake.lib = {
    inherit judgeCases;
    mkJudgeCheck = pkgs: args: judgeCases args (pkgs.runCommand args.name { } "touch $out");
  };
}
