# checks.x86_64-linux.secrets-seam-confinement: which modules name the secret
# backend, clan vars, outside the secret seam.
# `actual` is the sorted list of .nix files under modules/, `_`-prefixed ones
# included, with a line that is not a comment and names `clan.core.vars`,
# `vars/shared/` or `vars/per-machine/`. The two seam files,
# modules/system/secrets.nix (the backend's generators) and modules/lib/vars.nix
# (the committed layout), are outside both lists. `expected` is a literal list
# of the files that still name the backend. It is meant only to shrink, as
# modules move their secrets behind `vanixiets.secrets`, until it holds only
# the checks and runtime tests that must pin clan itself because they run a
# generator's script, lay out clan's on-disk vars, or judge the committed
# vars tree (the plan and each file's reason are in
# openspec/changes/seam-secrets-away-from-clan-vars/design.md). On failure the
# build prints each list one file per line and what to do.
#
# The rule matches text, line by line, so it does not see a read spelt any
# other way: `inherit (config.clan.core) vars;`, a quoted attribute name such
# as `clan.core."vars"`, a path built from strings, or any file outside
# modules/, such as pkgs/by-name/ntfy-send/package.nix.
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
    "modules/checks/commit-signing-key.nix"
    "modules/checks/fleet-deployer-obligations.nix"
    "modules/checks/greptimedb-envelope.nix"
    "modules/checks/host-key-obligations.nix"
    "modules/checks/langfuse-query.nix"
    "modules/checks/nix-builders-wiring.nix"
    "modules/checks/ntfy-provisioning.nix"
    "modules/checks/obs-query.nix"
    "modules/checks/omnigraph-retired-roots.nix"
    "modules/checks/secrets-seam-translation.nix"
    "modules/checks/sops-correspondence.nix"
    "modules/clan/services/hermes-agent/flake-module.nix"
    "modules/clan/services/nix-builders/flake-module.nix"
    "modules/clan/services/omnigent/flake-module.nix"
    "modules/clan/services/openclaw/flake-module.nix"
    "modules/clan/services/otel-collector/service.nix"
    "modules/clan/services/tincr/flake-module.nix"
    "modules/darwin/omnigent-host.nix"
    "modules/darwin/otel-collector-agent.nix"
    "modules/darwin/ssh-ca-trust.nix"
    "modules/effects/ironstar/secrets.nix"
    "modules/effects/vanixiets/secrets.nix"
    "modules/home/ai/omnigent/credentials.nix"
    "modules/home/development/vcs-signing.nix"
    "modules/home/users/lib.nix"
    "modules/lib/commit-signing.nix"
    "modules/lib/fleet-deployer.nix"
    "modules/lib/host-keys.nix"
    "modules/lib/omnigent-fleet-obligations.nix"
    "modules/lib/shared-vars-recipients.nix"
    "modules/machines/nixos/cinnabar/caddy-root-ca.nix"
    "modules/machines/nixos/cinnabar/caddy-root-check.nix"
    "modules/machines/nixos/cinnabar/fleet-alert.nix"
    "modules/machines/nixos/cinnabar/matrix.nix"
    "modules/machines/nixos/cinnabar/ntfy.nix"
    "modules/machines/nixos/cinnabar/radicle.nix"
    "modules/machines/nixos/cinnabar/zt-dns.nix"
    "modules/machines/nixos/magnetite/default.nix"
    "modules/machines/nixos/pyrite/disko.nix"
    "modules/nixos/fleet-alert-server.nix"
    "modules/nixos/fleet-deployer.nix"
    "modules/nixos/gitea-mq.nix"
    "modules/nixos/gitea.nix"
    "modules/nixos/greptimedb-server.nix"
    "modules/nixos/kanidm.nix"
    "modules/nixos/matrix.nix"
    "modules/nixos/niks3.nix"
    "modules/nixos/nixbot.nix"
    "modules/nixos/ntfy-alerter.nix"
    "modules/nixos/omnigent-host.nix"
    "modules/nixos/omnigent.nix"
    "modules/nixos/omnigraph-backup.nix"
    "modules/nixos/omnigraph-server.nix"
    "modules/nixos/perses-server.nix"
    "modules/nixos/postgresql-backup.nix"
    "modules/nixos/r2-usage.nix"
    "modules/nixos/renovate.nix"
    "modules/nixos/sso-gateway.nix"
    "modules/system/commit-signing-key.nix"
    "modules/system/initrd-networking.nix"
    "modules/system/stibnite-session.nix"
    "modules/vm-tests/clan-test-vars-fixture.nix"
    "modules/vm-tests/devloop-ingest.nix"
    "modules/vm-tests/fleet-ingress.nix"
    "modules/vm-tests/greptimedb-oom-order.nix"
    "modules/vm-tests/greptimedb-pipeline.nix"
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
