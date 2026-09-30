# Behavioural check for the effects interpreter's rendered script.
#
# That script is the only code an effect runs before its program, and it
# decides whether the program runs, with which secrets and which arguments.
# Each row renders a synthetic entry for one trigger kind (main, pullRequest,
# pullRequestClosed) through flake.lib.vanixietsEffectScript, the function
# modules/effects/vanixiets/registry.nix uses, runs it the way mkEffect's
# effectPhase does (eval of the script text), and asserts the exit status, the
# output, and exactly the argv and environment the program saw. Only main runs
# the guard and receives `--rev`; secrets and the forge token are exported per
# trigger. Rows marked "registry" render the vanixiets.effects entries
# themselves, program swapped for the stub, against a secrets file holding
# every secret, so a trigger that exported another trigger's secret would
# show it; in particular release-packages' pullRequest run never sees
# GITHUB_TOKEN. The secretsMap every registry trigger is granted is pinned
# too, through flake.lib.vanixietsEffectSecretsMap, the function mkEffect
# uses, since that map is what nixbot writes into the secrets file.
#
# The program is a stub that records its argv and the secret variables, and
# curl is stubbed for the nixbot id-token endpoint the main guard calls,
# as in checks.effect-run-context. Secret values are dummies.
{
  config,
  self,
  lib,
  ...
}:
let
  registry = config.vanixiets.effects;
in
{
  perSystem =
    { pkgs, ... }:
    let
      rev = "0123456789abcdef0123456789abcdef01234567";

      recordedVars = [
        "CLOUDFLARE_API_TOKEN"
        "CLOUDFLARE_ACCOUNT_ID"
        "GITHUB_TOKEN"
        "GITHUB_FORGE_TOKEN"
      ];

      stubProgram = pkgs.writeShellScript "stub-program" ''
        printf '%s\n' "$@" > "$PWD/argv"
        ${lib.concatMapStrings (var: ''
          printf '%s\n' "${var}=''${${var}-UNSET}" >> "$PWD/env"
        '') recordedVars}
      '';

      mkTokenResponse = claims: ''
        payload="$(printf '%s' ${lib.escapeShellArg (builtins.toJSON claims)} \
          | base64 -w0 | tr '+/' '-_' | tr -d '=')"
        printf '{"token":"eyJhbGciOiJSUzI1NiJ9.%s.signature"}' "$payload" > "$PWD/token.json"
      '';

      mainClaims = {
        event = "push";
        ref = "refs/heads/main";
      };

      row =
        {
          name,
          kind,
          entry ? null,
          trigger ? { },
          otherTriggers ? { },
          claims ? null,
          secretsJson,
          status,
          expect ? [ ],
          argv ? null,
          env ? null,
        }:
        let
          defaultTrigger = {
            args = [ ];
            secrets = [ ];
            forgeToken = false;
          };
          rendered =
            if entry != null then
              entry // { program = stubProgram; }
            else
              {
                program = stubProgram;
                triggers = lib.mapAttrs (_: other: defaultTrigger // other) otherTriggers // {
                  ${kind} = defaultTrigger // trigger;
                };
              };
          script = pkgs.writeText "effect-script.sh" (
            self.lib.vanixietsEffectScript { inherit rev; } kind rendered
          );
        in
        ''
          echo "--- ${name}"
          rm -rf "$TMPDIR/row" && mkdir "$TMPDIR/row" && cd "$TMPDIR/row"
          ${lib.optionalString (claims != null) (mkTokenResponse claims)}
          printf '%s' ${lib.escapeShellArg (builtins.toJSON secretsJson)} > secrets.json
          status=0
          env -i PATH="$PATH" HOME="$TMPDIR" \
            HERCULES_CI_SECRETS_JSON="$PWD/secrets.json" \
            NIXBOT_ID_TOKEN_REQUEST_URL=https://nixbot.invalid/api/v1/id-token \
            NIXBOT_ID_TOKEN_REQUEST_TOKEN=task-token \
            effectScript="$(cat ${script})" \
            ${lib.getExe pkgs.bash} -c 'eval "$effectScript"' > output 2>&1 || status=$?
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
          ${
            if argv == null then
              ''
                if [ -e argv ]; then
                  echo "row '${name}': the program ran" >&2
                  exit 1
                fi
              ''
            else
              ''
                printf '%s\n' ${lib.escapeShellArgs argv} > argv.expected
                diff -u argv.expected argv
                printf '%s\n' ${
                  lib.escapeShellArgs (map (var: "${var}=${env.${var} or "UNSET"}") recordedVars)
                } > env.expected
                diff -u env.expected env
              ''
          }
          ${lib.optionalString (kind != "main") ''
            if [ -e curl-calls ]; then
              echo "row '${name}': a ${kind} run ran the main-only guard" >&2
              exit 1
            fi
          ''}
        '';

      cloudflare.CLOUDFLARE_API_TOKEN.data.value = "dummy-cloudflare-token";
      cloudflareAccount.CLOUDFLARE_ACCOUNT_ID.data.value = "dummy-cloudflare-account";
      github.GITHUB_TOKEN.data.value = "dummy-github-token";
      forge.GITHUB_FORGE_TOKEN.data.token = "dummy-forge-token";
      everySecret = cloudflare // cloudflareAccount // github // forge;

      grantedSecrets = lib.mapAttrs (
        _: entry:
        lib.mapAttrs (_: trigger: builtins.attrNames (self.lib.vanixietsEffectSecretsMap trigger)) (
          lib.filterAttrs (_: trigger: trigger != null) entry.triggers
        )
      ) registry;
      expectedGrantedSecrets = {
        docs = {
          main = [
            "CLOUDFLARE_ACCOUNT_ID"
            "CLOUDFLARE_API_TOKEN"
          ];
          pullRequest = [
            "CLOUDFLARE_ACCOUNT_ID"
            "CLOUDFLARE_API_TOKEN"
            "GITHUB_FORGE_TOKEN"
          ];
          pullRequestClosed = [
            "CLOUDFLARE_ACCOUNT_ID"
            "CLOUDFLARE_API_TOKEN"
          ];
        };
        release-packages = {
          main = [ "GITHUB_TOKEN" ];
          pullRequest = [ "GITHUB_FORGE_TOKEN" ];
        };
      };
    in
    {
      checks.effects-interpreter =
        pkgs.runCommand "effects-interpreter"
          {
            nativeBuildInputs = [
              pkgs.jq
              pkgs.coreutils
              pkgs.diffutils
              pkgs.gnugrep
            ];
            meta.description = "behavioural check: effects interpreter script";
          }
          ''
            mkdir -p "$TMPDIR/bin"

            cat > "$TMPDIR/bin/curl" <<'STUB'
            #!/bin/sh
            echo "$*" >> "$PWD/curl-calls"
            [ -f "$PWD/token.json" ] || exit 7
            cat "$PWD/token.json"
            STUB
            chmod +x "$TMPDIR/bin/curl"
            export PATH="$TMPDIR/bin:$PATH"

            echo "--- registry secretsMap per trigger"
            printf '%s' ${lib.escapeShellArg (builtins.toJSON expectedGrantedSecrets)} | jq -S . > granted.expected
            printf '%s' ${lib.escapeShellArg (builtins.toJSON grantedSecrets)} | jq -S . > granted
            diff -u granted.expected granted

            ${lib.concatMapStrings row [
              {
                name = "main execs the program with --rev and its secrets";
                kind = "main";
                trigger.secrets = [
                  "CLOUDFLARE_API_TOKEN"
                  "GITHUB_TOKEN"
                ];
                trigger.args = [
                  "production"
                  "two words"
                  "$HOME"
                ];
                claims = mainClaims;
                secretsJson = cloudflare // github // forge;
                status = 0;
                expect = [ "CI-RUN-CONTEXT: branch=main is_main=true" ];
                argv = [
                  "production"
                  "two words"
                  "$HOME"
                  "--rev"
                  rev
                ];
                env = {
                  CLOUDFLARE_API_TOKEN = "dummy-cloudflare-token";
                  GITHUB_TOKEN = "dummy-github-token";
                };
              }
              {
                name = "main on a non-main token is skipped";
                kind = "main";
                trigger.secrets = [ "GITHUB_TOKEN" ];
                claims = {
                  event = "push";
                  ref = "refs/heads/gitea-mq/batch/7";
                };
                secretsJson = github;
                status = 0;
                expect = [
                  "EFFECT-GUARD: skipping outside a push to main (event=push ref=refs/heads/gitea-mq/batch/7)"
                ];
              }
              {
                name = "missing secret fails before the program runs";
                kind = "main";
                trigger.secrets = [
                  "CLOUDFLARE_API_TOKEN"
                  "GITHUB_TOKEN"
                ];
                claims = mainClaims;
                secretsJson = cloudflare;
                status = 1;
                expect = [ "error: GITHUB_TOKEN missing from $HERCULES_CI_SECRETS_JSON" ];
              }
              {
                name = "null secret fails before the program runs";
                kind = "main";
                trigger.secrets = [ "GITHUB_TOKEN" ];
                claims = mainClaims;
                secretsJson.GITHUB_TOKEN.data.value = null;
                status = 1;
                expect = [ "error: GITHUB_TOKEN missing from $HERCULES_CI_SECRETS_JSON" ];
              }
              {
                name = "pullRequest runs unguarded, without --rev, with the forge token";
                kind = "pullRequest";
                trigger = {
                  args = [ "pull-request" ];
                  secrets = [ "CLOUDFLARE_API_TOKEN" ];
                  forgeToken = true;
                };
                secretsJson = cloudflare // forge;
                status = 0;
                argv = [ "pull-request" ];
                env = {
                  CLOUDFLARE_API_TOKEN = "dummy-cloudflare-token";
                  GITHUB_FORGE_TOKEN = "dummy-forge-token";
                };
              }
              {
                name = "missing forge token fails before the program runs";
                kind = "pullRequest";
                trigger.forgeToken = true;
                secretsJson = cloudflare;
                status = 1;
                expect = [ "error: GITHUB_FORGE_TOKEN missing from $HERCULES_CI_SECRETS_JSON" ];
              }
              {
                name = "pullRequestClosed runs unguarded, without --rev, without the forge token";
                kind = "pullRequestClosed";
                trigger = {
                  args = [ "pull-request-closed" ];
                  secrets = [ "CLOUDFLARE_API_TOKEN" ];
                };
                secretsJson = cloudflare // forge;
                status = 0;
                argv = [ "pull-request-closed" ];
                env.CLOUDFLARE_API_TOKEN = "dummy-cloudflare-token";
              }
              {
                name = "missing secret fails a pullRequestClosed run before the program runs";
                kind = "pullRequestClosed";
                trigger = {
                  args = [ "pull-request-closed" ];
                  secrets = [ "CLOUDFLARE_API_TOKEN" ];
                };
                secretsJson = github;
                status = 1;
                expect = [ "error: CLOUDFLARE_API_TOKEN missing from $HERCULES_CI_SECRETS_JSON" ];
              }
              {
                name = "pullRequest never receives the main trigger's secrets";
                kind = "pullRequest";
                otherTriggers.main.secrets = [ "GITHUB_TOKEN" ];
                trigger.forgeToken = true;
                secretsJson = everySecret;
                status = 0;
                argv = [ ];
                env.GITHUB_FORGE_TOKEN = "dummy-forge-token";
              }
              {
                name = "main never receives the pullRequest trigger's secrets or forge token";
                kind = "main";
                otherTriggers.pullRequest = {
                  secrets = [ "CLOUDFLARE_API_TOKEN" ];
                  forgeToken = true;
                };
                trigger.secrets = [ "GITHUB_TOKEN" ];
                claims = mainClaims;
                secretsJson = everySecret;
                status = 0;
                argv = [
                  "--rev"
                  rev
                ];
                env.GITHUB_TOKEN = "dummy-github-token";
              }
              {
                name = "registry: release-packages pullRequest runs the plan with the forge token and never GITHUB_TOKEN";
                kind = "pullRequest";
                entry = registry.release-packages;
                secretsJson = everySecret;
                status = 0;
                argv = [ "plan" ];
                env.GITHUB_FORGE_TOKEN = "dummy-forge-token";
              }
              {
                name = "registry: release-packages pullRequest without the forge token fails before the program runs";
                kind = "pullRequest";
                entry = registry.release-packages;
                secretsJson = github;
                status = 1;
                expect = [ "error: GITHUB_FORGE_TOKEN missing from $HERCULES_CI_SECRETS_JSON" ];
              }
              {
                name = "registry: release-packages main receives GITHUB_TOKEN and not the forge token";
                kind = "main";
                entry = registry.release-packages;
                claims = mainClaims;
                secretsJson = everySecret;
                status = 0;
                expect = [ "CI-RUN-CONTEXT: branch=main is_main=true" ];
                argv = [
                  "--rev"
                  rev
                ];
                env.GITHUB_TOKEN = "dummy-github-token";
              }
              {
                name = "registry: docs pullRequestClosed receives Cloudflare and not the forge token";
                kind = "pullRequestClosed";
                entry = registry.docs;
                secretsJson = everySecret;
                status = 0;
                argv = [ "pull-request-closed" ];
                env = {
                  CLOUDFLARE_API_TOKEN = "dummy-cloudflare-token";
                  CLOUDFLARE_ACCOUNT_ID = "dummy-cloudflare-account";
                };
              }
            ]}

            touch $out
          '';
    };
}
