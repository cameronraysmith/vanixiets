# checks.x86_64-linux.secrets-seam-confinement: which modules name the secret
# backend, clan vars, outside the secret seam.
# `actual` is the sorted list of .nix files under modules/, `_`-prefixed ones
# included, with a line that is not a comment and names `clan.core.vars`,
# `vars/shared/` or `vars/per-machine/`. The two seam files,
# modules/system/secrets.nix (the backend's generators) and modules/lib/vars.nix
# (the committed layout), are outside both lists. `expected` is the literal
# list of the files allowed to name the backend, each with its reason: the
# checks and runtime tests that must pin clan itself because they run a
# generator's recipe, lay out clan's on-disk vars, judge the translation or
# the committed vars tree, or hold literal fixtures of clan's paths. Each
# would have to change if the backend were replaced, so they are named here
# rather than moved behind the seam (the reasons are also in
# openspec/changes/seam-secrets-away-from-clan-vars/design.md). Every other
# module declares and reads secrets through `vanixiets.secrets`. On failure
# the build prints each list one file per line and what to do.
#
# The rule matches text, line by line, so it does not see a read spelt any
# other way: `inherit (config.clan.core) vars;`, a quoted attribute name such
# as `clan.core."vars"`, a path built from strings, or any file outside
# modules/, such as pkgs/by-name/ntfy-send/package.nix. Nor does it see
# reads through `flake.lib.secretsBackend.generatorsOf`, which returns the
# backend's whole generator tree of a host; today modules/checks/nix-builders-wiring.nix,
# modules/home/ai/omnigent/credentials.nix and
# modules/lib/{commit-signing,fleet-deployer,host-keys,shared-vars-recipients}.nix
# use it.
{ lib, ... }:
let
  root = ../.;
  seam = [
    "modules/lib/vars.nix"
    "modules/system/secrets.nix"
  ];
  relative = file: "modules/" + lib.removePrefix "${toString root}/" (toString file);
  namesBackend =
    line:
    let
      text = lib.head (builtins.match "[[:space:]]*(.*)" line);
    in
    !lib.hasPrefix "#" text
    && (
      builtins.match ".*clan\\.core\\.vars.*" text != null
      || builtins.match ".*vars/(shared|per-machine)/.*" text != null
    );
  actual = lib.sort lib.lessThan (
    lib.filter (rel: !lib.elem rel seam) (
      map relative (
        lib.filter (
          file:
          lib.hasSuffix ".nix" (toString file)
          && lib.any namesBackend (lib.splitString "\n" (builtins.readFile file))
        ) (lib.filesystem.listFilesRecursive root)
      )
    )
  );
  expected = [
    # literal fixture: a fixture home's delivered key path (:95)
    "modules/checks/commit-signing-key.nix"
    # literal fixtures of committed vars paths (:152,207)
    "modules/checks/fleet-deployer-obligations.nix"
    # runs greptimedb-users' recipe (finalScript), and reads otel-cert's key.pem owner and mode from clan (:513)
    "modules/checks/greptimedb-envelope.nix"
    # literal fixtures: a stub of clan's generator tree for the presence test
    "modules/checks/host-key-obligations.nix"
    # encrypted files interpolated on purpose (:114)
    "modules/checks/langfuse-query.nix"
    # runs cinnabar's ntfy-alerter and ntfy-alerter-env recipes (finalScript)
    "modules/checks/ntfy-provisioning.nix"
    # independent judge of the translation; its fixture stubs clan's option
    "modules/checks/secrets-seam-translation.nix"
    # independent judge of the committed vars tree
    "modules/checks/sops-correspondence.nix"
    # lays out clan's on-disk vars for test nodes
    "modules/vm-tests/clan-test-vars-fixture.nix"
    # runs greptimedb-users' recipe (finalScript)
    "modules/vm-tests/devloop-ingest.nix"
    # runs greptimedb-users' recipe (finalScript)
    "modules/vm-tests/fleet-ingress.nix"
    # runs greptimedb-users' recipe (finalScript)
    "modules/vm-tests/greptimedb-oom-order.nix"
    # runs greptimedb-users' recipe (finalScript)
    "modules/vm-tests/greptimedb-pipeline.nix"
    # runs greptimedb-users' recipe (finalScript)
    "modules/vm-tests/perses-greptimedb.nix"
  ];
in
{
  perSystem =
    { pkgs, system, ... }:
    lib.optionalAttrs (system == "x86_64-linux") {
      testSizes.checks = {
        # nixbot: 0 runs, too few to class (declare-test-size-classes design D4)
        secrets-seam-confinement = {
          class = "medium";
          measured = false;
        };
      };
      # Built as flake.lib.mkStructuralCheck builds, from the two lists alone,
      # with one file per line so that a failure names each file on its own.
      checks.secrets-seam-confinement =
        pkgs.runCommand "structure-secrets-seam-confinement"
          {
            expectedText = lib.concatLines expected;
            actualText = lib.concatLines actual;
            passAsFile = [
              "expectedText"
              "actualText"
            ];
            meta.description = "structural check: secrets-seam-confinement";
          }
          ''
            if ! diff -u --label expected --label actual "$expectedTextPath" "$actualTextPath"; then
              echo ""
              echo "secrets-seam-confinement: a file marked + names the secret backend outside the seam: move its declarations and reads behind vanixiets.secrets (modules/system/secrets.nix), or, if it is a check or runtime test that must pin clan itself, add it to expected in modules/checks/secrets-seam-confinement.nix with a comment giving the reason. A file marked - no longer names it: delete it from expected."
              exit 1
            fi
            touch $out
          '';
    };
}
