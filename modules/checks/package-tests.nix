# Per-package passthru.tests build-realization checks.
#
# Exposes each declared pkg.passthru.tests.<tname> as
# package-${pname}-test-${tname}. Notably exercises vanixiets-docs's unit,
# linkcheck, e2e, e2e-report and negative-control test set. e2e-report exposes
# cacheable evidence to nixbot independently of the mandatory e2e verdict; a
# report artifact alone is not a passing test.
#
# The package and test names are declared here rather than read from
# self'.packages, so the check names are static: computing them never
# evaluates a package. Every check's value asserts that the declaration
# matches the passthru.tests of every package outside the packages.nix-shaped
# blacklist (entries already exposed under another check name or intentional
# effect-input-wires), so adding, removing or renaming a test fails each
# package test until this list is updated.
{ lib, ... }:
{
  perSystem =
    { self', ... }:
    let
      declared = {
        atomic = [ "help" ];
        playwright-cli = [ "smoke" ];
        stack-land = [ "integration" ];
        vanixiets-docs = [
          "e2e"
          "e2e-action-negative-control"
          "e2e-negative-control"
          "e2e-report"
          "e2e-runner-controls"
          "e2e-webkit-negative-control"
          "linkcheck"
          "typecheck"
          "unit"
        ];
      };

      blacklist = [
        "k8s-manifests-local"
        "k8s-manifests-local-json"
        "k8s-manifests-local-k3d"
        "k8s-manifests-local-k3d-json"
        "fdContainer-aarch64"
        "fdContainer-x86_64"
        "rgContainer-aarch64"
        "rgContainer-x86_64"
        "fdManifest"
        "fdManifest-aarch64"
        "fdManifest-x86_64"
        "rgManifest"
        "rgManifest-aarch64"
        "rgManifest-x86_64"
        "nix-fast-build"
      ];

      actual = lib.filterAttrs (_: tests: tests != [ ]) (
        lib.mapAttrs (_: pkg: builtins.attrNames (pkg.passthru.tests or { })) (
          lib.filterAttrs (n: _: !(builtins.elem n blacklist)) self'.packages
        )
      );

      declarationMatches = lib.assertMsg (actual == declared) (
        "modules/checks/package-tests.nix declares ${builtins.toJSON declared} "
        + "but the packages' passthru.tests are ${builtins.toJSON actual}"
      );
    in
    {
      checks = lib.concatMapAttrs (
        pname: tnames:
        lib.listToAttrs (
          map (
            tname:
            lib.nameValuePair "package-${pname}-test-${tname}" (
              assert declarationMatches;
              self'.packages.${pname}.passthru.tests.${tname}
            )
          ) tnames
        )
      ) declared;
    };
}
