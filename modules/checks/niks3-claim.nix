# Behavioural check of niks3-claim-without-exception.patch (F65): upstream's
# claim tests, built from the pinned niks3 input with flake.lib.niks3Patches,
# the same list magnetite's niks3-server is built with, plus
# ./niks3-claim/claim-test.patch. That test claims a key another push has
# committed, without a transaction, and fails unless the call answers
# needs_transaction and keeps no claim. The test PostgreSQL logs to the
# output, so the check also fails on any `claim needs a transaction` there.
# Upstream's tests start their own PostgreSQL and rustfs, as its
# go-unit-tests check does. Defined for x86_64-linux only: niks3 runs on
# magnetite.
{ config, inputs, ... }:
let
  flakeLib = config.flake.lib;
in
{
  perSystem =
    {
      lib,
      pkgs,
      system,
      ...
    }:
    let
      tests = inputs.niks3.packages.${system}.niks3-tests.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ flakeLib.niks3Patches ++ [ ./niks3-claim/claim-test.patch ];
      });

      niks3-claim =
        pkgs.runCommand "niks3-claim"
          {
            nativeBuildInputs = [
              tests
              pkgs.postgresql
              pkgs.rustfs
            ];
            meta.description = "behavioural check: niks3 claims narinfos without PostgreSQL logging an error";
          }
          ''
            export HOME=$TMPDIR
            export GOMAXPROCS=$NIX_BUILD_CORES
            # rustfs (via reqwest/rustls-native-certs) wants this
            export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
            niks3-server.test -test.run '^TestClaim_' -test.v 2>&1 | tee result.txt
            test "''${PIPESTATUS[0]}" -eq 0
            if grep -q 'claim needs a transaction' result.txt; then
              echo 'PostgreSQL logged a failed claim' >&2
              exit 1
            fi
            mkdir -p $out
            cp result.txt $out/
          '';
    in
    {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # nixbot: 1 run, too few to class (design D4)
        niks3-claim = {
          class = "medium";
          measured = false;
        };
      };
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        inherit niks3-claim;
      };
    };
}
