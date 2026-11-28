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
    { self', system, ... }:
    let
      declared = {
        atomic = [ "help" ];
        comment-gate = [ "self-test" ];
        ghq-shared = [
          "acl"
          "handler"
          "handler-history"
          "wrapper"
        ];
        ntfy-send = [
          "tls-verification"
          "token-transport"
        ];
        pi-acp = [ "initialize" ];
        playwright-cli = [ "smoke" ];
        stack-land = [ "integration" ];
        vanixiets-docs = [
          "e2e"
          "e2e-action-negative-control"
          "e2e-negative-control"
          "e2e-report"
          "e2e-runner-controls"
          "e2e-topology-negative-control"
          "e2e-webkit-negative-control"
          "linkcheck"
          "typecheck"
          "unit"
        ];
      }
      # pkgs/by-name/renovate is packaged for x86_64-linux only.
      // lib.optionalAttrs (system == "x86_64-linux") {
        renovate = [ "version" ];
      };

      blacklist = [
        "k8s-manifests-local-json"
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
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks =
        {
          x86_64-linux = {
            # nixbot: median 8.1 s, slowest 48 s, 3 runs in 30 days
            package-atomic-test-help.class = "small";
            package-comment-gate-test-self-test = {
              class = "medium";
              measured = false;
            };
            # nixbot: median 8.5 s, slowest 18 s, all 6 runs 2026-10-21..2026-11-11
            package-ghq-shared-test-acl.class = "small";
            # The handler's test split in two on 2026-11-27, the whole having run
            # 75 to 151 s on nixbot; no run of either half yet, too few to class
            # (design D4).
            package-ghq-shared-test-handler = {
              class = "small";
              measured = false;
            };
            package-ghq-shared-test-handler-history = {
              class = "small";
              measured = false;
            };
            # nixbot: median 7.8 s, slowest 18 s, all 5 runs 2026-10-21..2026-11-11
            package-ghq-shared-test-wrapper.class = "small";
            # nixbot: 1 run, too few to class (design D4)
            package-ntfy-send-test-tls-verification = {
              class = "medium";
              measured = false;
            };
            # nixbot: 2 runs, too few to class (design D4)
            package-ntfy-send-test-token-transport = {
              class = "medium";
              measured = false;
            };
            # nixbot: 0 runs, too few to class (design D4)
            package-pi-acp-test-initialize = {
              class = "medium";
              measured = false;
            };
            # nixbot: median 39 s, slowest 68 s, all 6 runs 2026-10-01..2026-11-11
            package-playwright-cli-test-smoke.class = "small";
            # no nixbot runs yet, too few to class
            package-renovate-test-version = {
              class = "medium";
              measured = false;
            };
            # nixbot: median 25 s, slowest 49 s, 5 runs in 30 days
            package-stack-land-test-integration.class = "small";
            # nixbot: median 2.1 s, slowest 306 s, 152 runs in 30 days
            package-vanixiets-docs-test-e2e.class = "small";
            # nixbot: median 49 s, slowest 315 s, 155 runs in 30 days
            package-vanixiets-docs-test-e2e-action-negative-control.class = "small";
            # nixbot: median 40 s, slowest 289 s, 153 runs in 30 days
            package-vanixiets-docs-test-e2e-negative-control.class = "small";
            # nixbot: median 47 s, slowest 364 s, 150 runs in 30 days
            package-vanixiets-docs-test-e2e-report.class = "small";
            # nixbot: median 30 s, slowest 237 s, 161 runs in 30 days
            package-vanixiets-docs-test-e2e-runner-controls.class = "small";
            # nixbot: median 32 s, slowest 126 s, 42 runs in 30 days
            package-vanixiets-docs-test-e2e-topology-negative-control.class = "small";
            # nixbot: median 48 s, slowest 344 s, 153 runs in 30 days
            package-vanixiets-docs-test-e2e-webkit-negative-control.class = "small";
            # nixbot: median 44 s, slowest 205 s, 152 runs in 30 days
            package-vanixiets-docs-test-linkcheck.class = "small";
            # nixbot: median 12 s, slowest 123 s, 157 runs in 30 days
            package-vanixiets-docs-test-typecheck.class = "small";
            # nixbot: median 26 s, slowest 163 s, 160 runs in 30 days
            package-vanixiets-docs-test-unit.class = "small";
          };
          aarch64-darwin = {
            # nixbot: median 26 s, slowest 92 s, 6 runs in 30 days
            package-atomic-test-help.class = "small";
            package-comment-gate-test-self-test = {
              class = "medium";
              measured = false;
            };
            # nixbot: median 65 s, slowest 649 s, 4 runs in 30 days
            package-ghq-shared-test-acl.class = "medium";
            # Split in two on 2026-11-27, the whole having a median of 125 s; no
            # run of either half yet, too few to class (design D4).
            package-ghq-shared-test-handler = {
              class = "medium";
              measured = false;
            };
            package-ghq-shared-test-handler-history = {
              class = "medium";
              measured = false;
            };
            # nixbot: median 48 s, slowest 601 s, 4 runs in 30 days
            package-ghq-shared-test-wrapper.class = "small";
            # nixbot: 2 runs, too few to class (design D4)
            package-ntfy-send-test-tls-verification = {
              class = "medium";
              measured = false;
            };
            # nixbot: median 165 s, slowest 406 s, all 4 runs 2026-10-18..2026-11-11
            package-ntfy-send-test-token-transport.class = "medium";
            # nixbot: 1 run, too few to class (design D4)
            package-pi-acp-test-initialize = {
              class = "medium";
              measured = false;
            };
            # nixbot: median 123 s, slowest 1260 s, all 4 runs 2026-10-07..2026-11-11
            package-playwright-cli-test-smoke.class = "medium";
            # nixbot: median 148 s, slowest 255 s, 4 runs in 30 days
            package-stack-land-test-integration.class = "medium";
            # nixbot: median 8.2 s, slowest 205 s, 125 runs in 30 days
            package-vanixiets-docs-test-e2e.class = "small";
            # nixbot: median 106 s, slowest 364 s, 126 runs in 30 days
            package-vanixiets-docs-test-e2e-action-negative-control.class = "medium";
            # nixbot: median 101 s, slowest 365 s, 126 runs in 30 days
            package-vanixiets-docs-test-e2e-negative-control.class = "medium";
            # nixbot: median 89 s, slowest 324 s, 128 runs in 30 days
            package-vanixiets-docs-test-e2e-report.class = "medium";
            # nixbot: median 84 s, slowest 463 s, 139 runs in 30 days
            package-vanixiets-docs-test-e2e-runner-controls.class = "medium";
            # nixbot: median 98 s, slowest 334 s, 37 runs in 30 days
            package-vanixiets-docs-test-e2e-topology-negative-control.class = "medium";
            # nixbot: median 102 s, slowest 389 s, 131 runs in 30 days
            package-vanixiets-docs-test-e2e-webkit-negative-control.class = "medium";
            # nixbot: median 97 s, slowest 498 s, 137 runs in 30 days
            package-vanixiets-docs-test-linkcheck.class = "medium";
            # nixbot: median 59 s, slowest 876 s, 141 runs in 30 days
            package-vanixiets-docs-test-typecheck.class = "small";
            # nixbot: median 77 s, slowest 372 s, 140 runs in 30 days
            package-vanixiets-docs-test-unit.class = "medium";
          };
        }
        .${system} or { };
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
