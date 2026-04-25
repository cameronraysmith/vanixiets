# Flake-level effects framework scaffolding.
#
# Imports the `hercules-ci-effects` flake-parts module so the top-level
# `herculesCI` output is wired to the schema consumed by buildbot-nix at
# `flake.outputs.herculesCI(args).onPush.default.outputs.effects` (per
# `buildbot-nix/buildbot_effects/buildbot_effects/__init__.py:142-159`).
#
# Per-job effects land under this same `onPush.default.outputs.effects.<name>`
# path. Branch gating is expressed in `buildbot-nix.toml`
# (`effects_branches`, `effects_on_pull_requests`), not the Nix attr path.
{ inputs, lib, ... }:
let
  # Effects execute on x86_64-linux (magnetite's buildbot-worker arch).
  pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;

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
        # effects.smoke — minimal diagnostic effect exercising the full
        # buildbot-nix + hercules-ci-effects pipeline end-to-end as a
        # reusable diagnostic baseline.
        #
        # Security invariants:
        #   - Prints only secret KEY NAMES, never VALUES.
        #   - Default-branch-only via `effects_branches = ["main"]` +
        #     `effects_on_pull_requests = false` (Posture A) in
        #     `buildbot-nix.toml`. No fork-PR or feature-branch exposure.
        smoke = hci-effects.mkEffect {
          name = "smoke";

          # buildbot-effects populates branch/rev/shortRev/tag from push
          # metadata; `toString` coerces a null tag to "" so interpolation
          # does not throw. `config.repo.ref` is intentionally NOT
          # referenced: buildbot-effects hard-codes `"ref": None` while
          # hercules-ci-effects declares `repo.ref` as non-nullable
          # `types.str`, so reading it would fail module type-checking.
          effectScript =
            let
              branch = toString (config.repo.branch or "");
              rev = toString (config.repo.rev or "");
              shortRev = toString (config.repo.shortRev or "");
              tag = toString (config.repo.tag or "");
            in
            ''
              set -euo pipefail

              echo "=== effects.smoke: buildbot-nix + hercules-ci-effects pipeline smoke test ==="

              # buildbot-effects-passed args (captured at Nix eval time via config.repo).
              echo "branch:   ${lib.escapeShellArg branch}"
              echo "rev:      ${lib.escapeShellArg rev}"
              echo "shortRev: ${lib.escapeShellArg shortRev}"
              echo "tag:      ${lib.escapeShellArg tag}"

              # HERCULES_CI_SECRETS_JSON is set by buildbot-nix inside
              # the bwrap sandbox to the path of the JSON secrets blob
              # produced by the `perRepoSecretFiles` pipeline (see
              # buildbot_effects/__init__.py:250-290).
              echo "HERCULES_CI_SECRETS_JSON=''${HERCULES_CI_SECRETS_JSON:-<unset>}"

              if [ -n "''${HERCULES_CI_SECRETS_JSON:-}" ] \
                 && [ -f "''${HERCULES_CI_SECRETS_JSON}" ]; then
                echo "secrets file exists: true"
                # Key-only enumeration. VALUES ARE INTENTIONALLY OMITTED.
                # Do not change this to `jq -r 'to_entries[] | .value'`
                # or equivalent — that would leak secret payloads to the
                # buildbot log.
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
