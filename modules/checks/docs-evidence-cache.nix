{ lib, ... }:
{
  perSystem =
    {
      pkgs,
      self',
      system,
      ...
    }:
    let
      docs = self'.packages.vanixiets-docs;
      first = docs.override { evidenceEpoch = "0"; };
      repeated = docs.override { evidenceEpoch = "0"; };
      refreshed = docs.override { evidenceEpoch = "1"; };
      invalid = builtins.tryEval (docs.override { evidenceEpoch = "invalid"; }).tests.e2e-report.drvPath;
      cases = {
        siteUnchanged = first.drvPath == refreshed.drvPath;
        identicalEpochReusesReport = first.tests.e2e-report.drvPath == repeated.tests.e2e-report.drvPath;
        freshEpochChangesReport = first.tests.e2e-report.drvPath != refreshed.tests.e2e-report.drvPath;
        freshEpochChangesVerdict = first.tests.e2e.drvPath != refreshed.tests.e2e.drvPath;
        invalidEpochRejected = !invalid.success;
        # The e2e verdict must judge the e2e-report it ships beside, not some
        # other producer's results.
        verdictConsumesReport = builtins.hasAttr (builtins.unsafeDiscardStringContext docs.tests.e2e-report.drvPath) (
          builtins.getContext docs.tests.e2e.buildCommand
        );
      };
    in
    {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks =
        {
          x86_64-linux = {
            # nixbot: median 1.7 s, slowest 3.2 s, all 5 runs 2026-10-02..2026-11-11
            docs-evidence-cache.class = "small";
          };
          aarch64-darwin = {
            # nixbot: median 12 s, slowest 25 s, all 4 runs 2026-10-04..2026-11-11
            docs-evidence-cache.class = "small";
          };
        }
        .${system} or { };
      checks.docs-evidence-cache =
        assert lib.assertMsg (lib.all lib.id (builtins.attrValues cases)) (
          "Docs evidence cache contract failed: "
          + lib.concatStringsSep ", " (builtins.attrNames (lib.filterAttrs (_: passed: !passed) cases))
        );
        pkgs.runCommand "docs-evidence-cache" { passthru = { inherit cases; }; } ''
          touch "$out"
        '';
    };
}
