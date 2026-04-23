# Flake-level effects framework scaffolding (M2 — mission ADR-001).
#
# Imports the `hercules-ci-effects` flake-parts module so that the
# top-level flake output `herculesCI` is wired to the schema consumed
# by buildbot-nix (`flake.outputs.herculesCI(args).onPush.default.outputs.effects`,
# per `buildbot-nix/buildbot_effects/buildbot_effects/__init__.py:142-159`).
#
# Per-job effects land under this same `onPush.default.outputs.effects.<name>`
# path (M3 smoke, M4 per-job cutover). Branch gating is expressed in
# `buildbot-nix.toml` (`effects_branches`, `effects_on_pull_requests`),
# not in the Nix attribute path.
#
# See `docs/notes/development/ci-cd/decisions/ADR-001-cd-to-buildbot-migration.md`
# for the full rationale and the fixed-attribute-path contract.
{ inputs, lib, ... }:
let
  # Effects execute on x86_64-linux (magnetite's buildbot-worker arch).
  pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;

  # `lib.withPkgs` returns the hercules-ci-effects helper set
  # (mkEffect, runIf, modularEffect, ...). See
  # hercules-ci-effects/flake-public-outputs.nix `lib.withPkgs`.
  hci-effects = inputs.hercules-ci-effects.lib.withPkgs pkgs;
in
{
  imports = [
    inputs.hercules-ci-effects.flakeModule
  ];

  herculesCI =
    { config, ... }:
    {
      onPush.default.outputs.effects = {
        # effects.smoke — minimal diagnostic effect (M3 feature `m3-deploy-smoke`).
        #
        # Purpose: exercise the full buildbot-nix + hercules-ci-effects
        # pipeline end-to-end (flake eval → nix-eval builder discovery →
        # `run-effect` builder scheduling → bwrap execution →
        # `HERCULES_CI_SECRETS_JSON` read → masked key enumeration → exit 0).
        # Establishes a reusable diagnostic baseline for M4 per-job effects.
        #
        # Security invariants:
        #   - Prints only secret KEY NAMES, never VALUES (uses
        #     `jq -r 'to_entries | map(.key) | @csv'`).
        #   - Default-branch-only via `effects_branches = ["main"]` +
        #     `effects_on_pull_requests = false` (Posture A) in
        #     `buildbot-nix.toml`. No fork-PR or feature-branch exposure.
        #
        # Verification: see VAL-PROVISIONING-SMOKE-00{1..9} in
        # `.factory/mission/validation-contract.md`.
        smoke = hci-effects.mkEffect {
          name = "smoke";

          # buildbot-effects populates these from the push metadata.
          # `toString` coerces `null` (unset tag/branch) to the empty
          # string so Nix string interpolation does not throw during
          # eval of the effect derivation.
          effectScript =
            let
              branch = toString (config.repo.branch or "");
              ref = toString (config.repo.ref or "");
              rev = toString (config.repo.rev or "");
              shortRev = toString (config.repo.shortRev or "");
              tag = toString (config.repo.tag or "");
            in
            ''
              set -euo pipefail

              echo "=== effects.smoke: buildbot-nix + hercules-ci-effects pipeline smoke test ==="

              # buildbot-effects-passed args (captured at Nix eval time via config.repo).
              echo "branch:   ${lib.escapeShellArg branch}"
              echo "ref:      ${lib.escapeShellArg ref}"
              echo "rev:      ${lib.escapeShellArg rev}"
              echo "shortRev: ${lib.escapeShellArg shortRev}"
              echo "tag:      ${lib.escapeShellArg tag}"

              # HERCULES_CI_SECRETS_JSON is set by buildbot-nix inside the
              # bwrap sandbox to the path of the JSON secrets blob produced
              # by the `perRepoSecretFiles` pipeline. See
              # buildbot-nix/buildbot_effects/buildbot_effects/__init__.py:250-290.
              echo "HERCULES_CI_SECRETS_JSON=''${HERCULES_CI_SECRETS_JSON:-<unset>}"

              if [ -n "''${HERCULES_CI_SECRETS_JSON:-}" ] \
                 && [ -f "''${HERCULES_CI_SECRETS_JSON}" ]; then
                echo "secrets file exists: true"
                # Key-only enumeration. VALUES ARE INTENTIONALLY OMITTED.
                # Do not change this to `jq -r 'to_entries[] | .value'`
                # or equivalent — that would leak secret payloads to the
                # buildbot log (VAL-PROVISIONING-SMOKE-006).
                echo -n "secret keys: "
                jq -r 'to_entries | map(.key) | @csv' \
                  "''${HERCULES_CI_SECRETS_JSON}"
              else
                echo "secrets file exists: false"
              fi

              echo "=== smoke effect complete (exit 0) ==="
            '';
        };
      };
    };
}
