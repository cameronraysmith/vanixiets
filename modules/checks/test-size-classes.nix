# checks.<system>.test-size-classes: every check on the pull-request gate and
# every runtime test carries a declared size class, no entry is orphaned, no
# check on the gate is enormous, and every large check records its reason
# (openspec/changes/declare-test-size-classes design D5, regulator G4).
#
# The gate evaluates checks.x86_64-linux and checks.aarch64-darwin, so the
# check exists on those two systems and each compares its own system's check
# names with its testSizes.checks entries. The x86_64-linux one also compares
# the vmTests names of x86_64-linux and aarch64-linux with those systems'
# testSizes.vmTests entries; runtime tests stay off the gate, so an enormous
# one is allowed. checks.aarch64-linux is not classed: nothing builds it.
#
# The findings are computed at evaluation from key sets and the literal
# entries only, so evaluating the check forces no other check's or test's
# derivation; the derivation prints them and fails when there are any.
{ lib, withSystem, ... }:
let
  gated = [
    "x86_64-linux"
    "aarch64-darwin"
  ];

  # The findings for one kind of attribute on one system: names without an
  # entry and entries naming nothing, then, for checks, the classes the gate
  # refuses.
  findingsFor =
    {
      path,
      names,
      entries,
      gate,
    }:
    let
      declared = builtins.attrNames entries;
      present = lib.filterAttrs (n: _: builtins.elem n names) entries;
    in
    map (n: "${path}.${n} has no testSizes entry; declare its size class beside its definition") (
      lib.subtractLists declared names
    )
    ++ map (n: "testSizes entry ${path}.${n} names no attribute; remove it or restore the attribute") (
      lib.subtractLists names declared
    )
    ++ lib.optionals gate (
      map (n: "${path}.${n} is enormous; an enormous check never gates a pull request") (
        builtins.attrNames (lib.filterAttrs (_: e: e.class == "enormous") present)
      )
      ++ map (n: "${path}.${n} is large and records no reason; give its reason beside its definition") (
        builtins.attrNames (
          lib.filterAttrs (_: e: e.class == "large" && (e.reason == null || e.reason == "")) present
        )
      )
    );

  vmTestsOf =
    system:
    withSystem system (
      { config, ... }:
      findingsFor {
        path = "vmTests.${system}";
        names = builtins.attrNames config.vmTests;
        entries = config.testSizes.vmTests;
        gate = false;
      }
    );
in
{
  perSystem =
    {
      config,
      pkgs,
      system,
      ...
    }:
    let
      onGate = builtins.elem system gated;
      findings =
        findingsFor {
          path = "checks.${system}";
          names = builtins.attrNames config.checks;
          entries = config.testSizes.checks;
          gate = true;
        }
        ++ lib.optionals (system == "x86_64-linux") (vmTestsOf "x86_64-linux" ++ vmTestsOf "aarch64-linux");
    in
    {
      # Size class: a leaf whose build prints a list and exits; it built in
      # under a second on Magnetite's store and on stibnite on 2026-11-24
      # (logs/tsc-4-build-20261124-142554.log).
      testSizes.checks = lib.optionalAttrs onGate {
        test-size-classes.class = "small";
      };

      checks = lib.optionalAttrs onGate {
        test-size-classes =
          pkgs.runCommand "test-size-classes"
            {
              findings = lib.concatLines findings;
              passthru = { inherit findings; };
            }
            ''
              if [ -n "$findings" ]; then
                echo "test-size-classes: ${toString (builtins.length findings)} finding(s):" >&2
                printf '%s' "$findings" >&2
                exit 1
              fi
              touch $out
            '';
      };
    };
}
