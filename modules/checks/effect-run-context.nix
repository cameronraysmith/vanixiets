# Behavioural check for the effects' main-only guard.
#
# The fragment in modules/lib/effect-run-context.nix is the backstop that stops
# an effect, and so its secrets, from running for anything but a push to main.
# What matters is the verdict on each token nixbot might mint and on each way
# the fetch can fail, and none of that is visible by reading the generated
# script. Every row runs the fragment as an effect would, first in a
# `set -euo pipefail` script, and asserts its exit status and output.
#
# curl is stubbed. What is under test is claim decoding and the verdict, not
# curl's argument handling; the request form itself matches nixbot's own
# end-to-end check, and a build sandbox has no server to call.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      runContext = self.lib.effectRunContext;

      effectScript = pkgs.writeText "guarded-effect.sh" ''
        set -euo pipefail
        ${runContext.mainOnlyGuard}
        echo "EFFECT-BODY: CI_BRANCH=$CI_BRANCH"
      '';

      # A JWT is header.payload.signature with an unpadded base64url payload.
      # Only the payload is read, so the other two fields are placeholders.
      mkTokenResponse = claims: ''
        payload="$(printf '%s' ${lib.escapeShellArg (builtins.toJSON claims)} \
          | base64 -w0 | tr '+/' '-_' | tr -d '=')"
        printf '{"token":"eyJhbGciOiJSUzI1NiJ9.%s.signature"}' "$payload" > "$PWD/token.json"
      '';

      # Each row runs the effect in a fresh directory. Without claims no
      # token.json exists and the curl stub fails as an unreachable server would.
      row =
        {
          name,
          claims ? null,
          env ? {
            NIXBOT_ID_TOKEN_REQUEST_URL = "https://nixbot.invalid/api/v1/id-token";
            NIXBOT_ID_TOKEN_REQUEST_TOKEN = "task-token";
          },
          status,
          expect,
        }:
        ''
          echo "--- ${name}"
          rm -rf "$TMPDIR/row" && mkdir "$TMPDIR/row" && cd "$TMPDIR/row"
          ${if claims == null then "" else mkTokenResponse claims}
          status=0
          env -u NIXBOT_ID_TOKEN_REQUEST_URL -u NIXBOT_ID_TOKEN_REQUEST_TOKEN \
            ${lib.concatStringsSep " " (lib.mapAttrsToList (n: v: "${n}=${lib.escapeShellArg v}") env)} \
            bash ${effectScript} > output 2>&1 || status=$?
          cat output
          if [ "$status" != ${toString status} ]; then
            echo "row '${name}': exit status $status, expected ${toString status}" >&2
            exit 1
          fi
          ${lib.concatMapStrings (line: ''
            if ! grep -qxF ${lib.escapeShellArg line} output; then
              echo "row '${name}': missing output line: "${lib.escapeShellArg line} >&2
              exit 1
            fi
          '') expect}
          ${lib.optionalString (!lib.any (lib.hasPrefix "EFFECT-BODY:") expect) ''
            if grep -q '^EFFECT-BODY:' output; then
              echo "row '${name}': effect body ran after the guard stopped it" >&2
              exit 1
            fi
          ''}
        '';
    in
    {
      checks.effect-run-context =
        pkgs.runCommand "effect-run-context"
          {
            nativeBuildInputs = [
              pkgs.jq
              pkgs.coreutils
              pkgs.gnugrep
            ];
            meta.description = "behavioural check: effect main-only guard";
          }
          ''
            mkdir -p "$TMPDIR/bin"

            # The fragment's only network call. It serves the token the row
            # wrote, or fails as curl -f does on an unreachable server.
            cat > "$TMPDIR/bin/curl" <<'STUB'
            #!/bin/sh
            [ -f "$PWD/token.json" ] || exit 7
            cat "$PWD/token.json"
            STUB
            chmod +x "$TMPDIR/bin/curl"
            export PATH="$TMPDIR/bin:$PATH"

            ${lib.concatMapStrings row [
              {
                name = "push to main runs";
                claims = {
                  event = "push";
                  ref = "refs/heads/main";
                };
                status = 0;
                expect = [
                  "CI-RUN-CONTEXT: branch=main is_main=true"
                  "EFFECT-BODY: CI_BRANCH=main"
                ];
              }
              {
                name = "push to a gitea-mq batch branch is skipped";
                claims = {
                  event = "push";
                  ref = "refs/heads/gitea-mq/batch/7";
                };
                status = 0;
                expect = [
                  "EFFECT-GUARD: skipping outside a push to main (event=push ref=refs/heads/gitea-mq/batch/7)"
                ];
              }
              {
                name = "pull request against main is skipped";
                claims = {
                  event = "pull_request";
                  pr_number = 42;
                  base_ref = "refs/heads/main";
                };
                status = 0;
                expect = [
                  "EFFECT-GUARD: skipping outside a push to main (event=pull_request ref=)"
                ];
              }
              {
                name = "missing id-token endpoint is refused";
                claims = {
                  event = "push";
                  ref = "refs/heads/main";
                };
                env.NIXBOT_ID_TOKEN_REQUEST_TOKEN = "task-token";
                status = 1;
                expect = [
                  "EFFECT-GUARD: NIXBOT_ID_TOKEN_REQUEST_URL and NIXBOT_ID_TOKEN_REQUEST_TOKEN are required; declare idTokenAudiences on the effect"
                ];
              }
              {
                name = "failed token fetch is refused";
                status = 1;
                expect = [ "EFFECT-GUARD: failed to obtain an id token from nixbot" ];
              }
            ]}

            touch $out
          '';
    };
}
