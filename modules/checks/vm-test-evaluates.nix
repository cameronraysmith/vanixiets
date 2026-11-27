# checks.x86_64-linux.vm-test-evaluates-<name>: the runtime test
# vmTests.x86_64-linux.<name> evaluates.
#
# nixbot evaluates and builds one attribute, `checks` (nixbot.toml), so without
# these the runtime tests are evaluated only by the weekly
# enormous-tests.service on pyrite and on demand. Each check is a text file
# holding one test's drvPath with the string context discarded: evaluating it
# instantiates that test, with nixbot's settings (import-from-derivation off),
# and building it builds nothing of the test. A test that does not evaluate
# fails its own check's evaluation, and the error names it ("while evaluating
# vmTests.x86_64-linux.<name>").
#
# One check per test keeps each evaluator worker to one test's evaluation; a
# single attribute forcing every test held them all in one worker, about
# 12.3 GiB under iets on magnetite on 2026-11-27, against nixbot's 3072 MiB
# per-worker share.
#
# The names come from vmTests' key set, which depends only on literals and
# `system`, so no test is evaluated to compute them. testSizes.checks lists
# them literally; checks.x86_64-linux.test-size-classes fails when a test has
# no entry here or an entry names no test.
{ lib, ... }:
{
  perSystem =
    {
      config,
      pkgs,
      system,
      ...
    }:
    {
      # No nixbot run backs a class yet.
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        vm-test-evaluates-caddy-root-from-vars = {
          class = "medium";
          measured = false;
        };
        vm-test-evaluates-devloop-ingest = {
          class = "medium";
          measured = false;
        };
        vm-test-evaluates-devloop-ingest-reconcile = {
          class = "medium";
          measured = false;
        };
        vm-test-evaluates-fleet-deployer = {
          class = "medium";
          measured = false;
        };
        vm-test-evaluates-fleet-ingress = {
          class = "medium";
          measured = false;
        };
        vm-test-evaluates-fleet-ingress-outage = {
          class = "medium";
          measured = false;
        };
        vm-test-evaluates-greptimedb-oom-order = {
          class = "medium";
          measured = false;
        };
        vm-test-evaluates-greptimedb-pipeline = {
          class = "medium";
          measured = false;
        };
        vm-test-evaluates-omnigent-worker-isolation = {
          class = "medium";
          measured = false;
        };
        vm-test-evaluates-omnigraph-local-root = {
          class = "medium";
          measured = false;
        };
        vm-test-evaluates-omnigraph-seed = {
          class = "medium";
          measured = false;
        };
        vm-test-evaluates-omnigraph-state-directory-transitions = {
          class = "medium";
          measured = false;
        };
        vm-test-evaluates-perses-greptimedb = {
          class = "medium";
          measured = false;
        };
        vm-test-evaluates-postgresql-backup-restore = {
          class = "medium";
          measured = false;
        };
        vm-test-evaluates-shared-reference-tree = {
          class = "medium";
          measured = false;
        };
        vm-test-evaluates-shared-reference-tree-migration = {
          class = "medium";
          measured = false;
        };
        vm-test-evaluates-tincr-mesh = {
          class = "medium";
          measured = false;
        };
        vm-test-evaluates-tincr-mesh-partition = {
          class = "medium";
          measured = false;
        };
        vm-test-evaluates-tuwunel-server-name-guard = {
          class = "medium";
          measured = false;
        };
        vm-test-evaluates-zerotier-mss-clamp-runtime = {
          class = "medium";
          measured = false;
        };
        vm-test-evaluates-zerotier-mss-clamp-runtime-nftables = {
          class = "medium";
          measured = false;
        };
      };
      checks = lib.optionalAttrs (system == "x86_64-linux") (
        lib.mapAttrs' (
          name: test:
          lib.nameValuePair "vm-test-evaluates-${name}" (
            pkgs.writeText "vm-test-evaluates-${name}" (
              builtins.addErrorContext "while evaluating vmTests.${system}.${name} (checks.${system}.vm-test-evaluates-${name})" (
                builtins.unsafeDiscardStringContext test.drvPath
              )
            )
          )
        ) config.vmTests
      );
    };
}
