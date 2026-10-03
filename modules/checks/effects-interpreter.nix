# Behavioural check for the effects interpreter's rendered script.
#
# That script is the only code an effect runs before its program, and it
# decides whether the program runs, with which secrets and which arguments.
# Rows render synthetic entries through flake.lib.vanixietsEffectScript,
# the function modules/effects/vanixiets/registry.nix uses for main,
# pullRequest, pullRequestClosed and buildFinished, run it the way mkEffect's
# effectPhase does (eval of the script text), and assert the exit status, the
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
# buildFinished rows use the actual onEvent.build_finished effectScript from
# an isolated registry evaluation, so a broken event mapping cannot pass by
# testing the renderer alone. The live browser-evidence registration, read
# from the flake's herculesCI output, is pinned too: it is an onEvent
# pull_request and build_finished effect, its build_finished `when` selects
# failed builds only, neither carries `when.permission` (trust is nixbot's CI
# approval), and all three runs share one lock, since build_finished may
# carry no pull request to expand {pr}. Rows passing nixbot's
# NIXBOT_API_URL/NIXBOT_API_TOKEN show the rendered script leaves them in
# the program's environment.
#
# The program is a stub that records its argv and the secret variables, and
# curl is stubbed for the nixbot id-token endpoint the main guard calls,
# as in checks.effect-run-context. Secret values are dummies.
{
  config,
  self,
  lib,
  inputs,
  withSystem,
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
        "R2_EVIDENCE_ACCESS_KEY_ID"
        "R2_EVIDENCE_SECRET_ACCESS_KEY"
        "NIXBOT_API_URL"
        "NIXBOT_API_TOKEN"
      ];

      stubProgram = pkgs.writeShellScript "stub-program" ''
        for arg in "$@"; do
          printf '%s\n' "$arg"
        done > "$PWD/argv"
        ${lib.concatMapStrings (var: ''
          printf '%s\n' "${var}=''${${var}-UNSET}" >> "$PWD/env"
        '') recordedVars}
      '';

      # Evaluate the production registry in isolation: these entries never
      # register live effects, but exercise its option defaults and onEvent map.
      fixture = lib.evalModules {
        specialArgs = { inherit inputs withSystem; };
        modules = [
          ../effects/vanixiets/registry.nix
          {
            options.flake.lib = lib.mkOption { type = lib.types.attrs; };
            options.herculesCI = lib.mkOption { type = lib.types.raw; };
            config = {
              flake.lib = {
                inherit (self.lib) effectRunContext vanixietsEffectSecrets;
              };
              vanixiets.effects = {
                finished = {
                  program = stubProgram;
                  rehearsals = [ pkgs.emptyFile ];
                  triggers.buildFinished = {
                    lock = "finished";
                    args = [
                      "two words"
                      "$HOME"
                      "it's literal"
                      ""
                    ];
                    secrets = [ "CLOUDFLARE_API_TOKEN" ];
                    forgeToken = true;
                    when = {
                      permission = "write";
                      branches = [
                        "main"
                        "release/*"
                      ];
                      status = [ "succeeded" ];
                      transition = "fixed";
                    };
                  };
                  triggers.main = {
                    lock = "main";
                    secrets = [ "GITHUB_TOKEN" ];
                  };
                };
                defaults = {
                  program = stubProgram;
                  rehearsals = [ pkgs.emptyFile ];
                  triggers.buildFinished.lock = "defaults";
                };
                omitted = {
                  program = stubProgram;
                  rehearsals = [ pkgs.emptyFile ];
                  triggers.pullRequest.lock = "omitted";
                };
              };
            };
          }
        ];
      };
      fixtureOutputs = fixture.config.herculesCI { config.repo = { inherit rev; }; };
      liveOutputs = self.herculesCI {
        primaryRepo = {
          inherit rev;
          ref = "refs/heads/main";
          branch = "main";
          tag = null;
          owner = "cameronraysmith";
          name = "vanixiets";
          remoteHttpUrl = "https://github.com/cameronraysmith/vanixiets";
          shortRev = builtins.substring 0 7 rev;
          forgeType = "github";
          webUrl = null;
        };
        herculesCI = { };
      };
      finishedEffects = fixtureOutputs.onEvent.build_finished;
      structural = {
        eventNames = builtins.attrNames finishedEffects;
        mainNames = builtins.attrNames fixtureOutputs.onPush.default.outputs.effects;
        pullRequestNames = builtins.attrNames fixtureOutputs.onEvent.pull_request;
        closedNames = builtins.attrNames fixtureOutputs.onEvent.pull_request_closed;
        omitted = fixture.config.vanixiets.effects.omitted.triggers.buildFinished;
        defaults = fixture.config.vanixiets.effects.defaults.triggers;
        lock = finishedEffects.finished.lock;
        secretsMap = builtins.fromJSON finishedEffects.finished.secretsMap;
        defaultSecretsMap = builtins.fromJSON finishedEffects.defaults.secretsMap;
        hasAudience = finishedEffects.finished ? idTokenAudiences;
        when = finishedEffects.finished.when;
        defaultWhen = finishedEffects.defaults.when;
        liveFinished = builtins.attrNames (
          lib.filterAttrs (_: entry: entry.triggers.buildFinished != null) registry
        );
        # The live browser-evidence registration nixbot receives, read from
        # the flake's herculesCI output rather than the registry.
        livePullRequest = builtins.attrNames liveOutputs.onEvent.pull_request;
        liveFinishedWhen = lib.mapAttrs (_: effect: effect.when) liveOutputs.onEvent.build_finished;
        livePullRequestHasWhen = liveOutputs.onEvent.pull_request.browser-evidence ? when;
        liveEvidenceLocks = {
          pullRequest = liveOutputs.onEvent.pull_request.browser-evidence.lock;
          buildFinished = liveOutputs.onEvent.build_finished.browser-evidence.lock;
          main = liveOutputs.onPush.default.outputs.effects.browser-evidence.lock;
        };
      };
      expectedStructural = {
        eventNames = [
          "defaults"
          "finished"
        ];
        mainNames = [ "finished" ];
        pullRequestNames = [ "omitted" ];
        closedNames = [ ];
        omitted = null;
        defaults = {
          main = null;
          pullRequest = null;
          pullRequestClosed = null;
          buildFinished = {
            lock = "defaults";
            args = [ ];
            secrets = [ ];
            forgeToken = false;
            when = {
              permission = null;
              branches = [ ];
              status = [ ];
              transition = null;
            };
          };
        };
        lock = "finished";
        secretsMap = {
          CLOUDFLARE_API_TOKEN = "CLOUDFLARE_API_TOKEN";
          GITHUB_FORGE_TOKEN.type = "GitToken";
        };
        defaultSecretsMap = { };
        hasAudience = false;
        when = {
          permission = "write";
          branches = [
            "main"
            "release/*"
          ];
          status = [ "succeeded" ];
          transition = "fixed";
        };
        defaultWhen = { };
        liveFinished = [ "browser-evidence" ];
        livePullRequest = [
          "browser-evidence"
          "docs"
          "release-packages"
        ];
        liveFinishedWhen.browser-evidence.status = [ "failed" ];
        livePullRequestHasWhen = false;
        liveEvidenceLocks = {
          pullRequest = "browser-evidence";
          buildFinished = "browser-evidence";
          main = "browser-evidence";
        };
      };

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
          effectScript ? null,
          claims ? null,
          secretsJson,
          status,
          expect ? [ ],
          argv ? null,
          env ? null,
          nixbotApi ? false,
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
            if effectScript != null then
              effectScript
            else
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
            ${lib.optionalString nixbotApi "NIXBOT_API_URL=https://nixbot.invalid NIXBOT_API_TOKEN=task-token"} \
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
                printf '%s' ${lib.escapeShellArg (lib.concatMapStrings (arg: arg + "\n") argv)} > argv.expected
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
      r2.R2_EVIDENCE_ACCESS_KEY_ID.data.value = "dummy-r2-access-key-id";
      r2.R2_EVIDENCE_SECRET_ACCESS_KEY.data.value = "dummy-r2-secret-access-key";
      everySecret = cloudflare // cloudflareAccount // github // forge // r2;
      r2Env = {
        CLOUDFLARE_ACCOUNT_ID = "dummy-cloudflare-account";
        R2_EVIDENCE_ACCESS_KEY_ID = "dummy-r2-access-key-id";
        R2_EVIDENCE_SECRET_ACCESS_KEY = "dummy-r2-secret-access-key";
        NIXBOT_API_URL = "https://nixbot.invalid";
        NIXBOT_API_TOKEN = "task-token";
      };

      grantedSecrets = lib.mapAttrs (
        _: entry:
        lib.mapAttrs (_: trigger: builtins.attrNames (self.lib.vanixietsEffectSecretsMap trigger)) (
          lib.filterAttrs (_: trigger: trigger != null) entry.triggers
        )
      ) registry;
      expectedGrantedSecrets = {
        browser-evidence =
          let
            r2Secrets = [
              "CLOUDFLARE_ACCOUNT_ID"
              "R2_EVIDENCE_ACCESS_KEY_ID"
              "R2_EVIDENCE_SECRET_ACCESS_KEY"
            ];
          in
          {
            pullRequest = r2Secrets;
            buildFinished = r2Secrets;
            main = r2Secrets;
          };
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

            echo "--- build_finished registry mapping and defaults"
            printf '%s' ${lib.escapeShellArg (builtins.toJSON expectedStructural)} | jq -S . > structural.expected
            printf '%s' ${lib.escapeShellArg (builtins.toJSON structural)} | jq -S . > structural
            diff -u structural.expected structural

            ${lib.concatMapStrings row [
              {
                name = "buildFinished maps to an unguarded event with literal argv and only its own secrets";
                kind = "buildFinished";
                effectScript = finishedEffects.finished.effectScript;
                secretsJson = everySecret;
                status = 0;
                argv = [
                  "two words"
                  "$HOME"
                  "it's literal"
                  ""
                ];
                env = {
                  CLOUDFLARE_API_TOKEN = "dummy-cloudflare-token";
                  GITHUB_FORGE_TOKEN = "dummy-forge-token";
                };
              }
              {
                name = "buildFinished defaults grant no secrets and append no revision";
                kind = "buildFinished";
                effectScript = finishedEffects.defaults.effectScript;
                secretsJson = everySecret;
                status = 0;
                argv = [ ];
                env = { };
              }
              {
                name = "buildFinished missing declared secret fails before the program runs";
                kind = "buildFinished";
                effectScript = finishedEffects.finished.effectScript;
                secretsJson = forge;
                status = 1;
                expect = [ "error: CLOUDFLARE_API_TOKEN missing from $HERCULES_CI_SECRETS_JSON" ];
              }
              {
                name = "buildFinished missing forge token fails before the program runs";
                kind = "buildFinished";
                effectScript = finishedEffects.finished.effectScript;
                secretsJson = cloudflare;
                status = 1;
                expect = [ "error: GITHUB_FORGE_TOKEN missing from $HERCULES_CI_SECRETS_JSON" ];
              }
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
              {
                name = "registry: browser-evidence buildFinished uploads with the R2 secrets and nixbot's API token, without --rev";
                kind = "buildFinished";
                entry = registry.browser-evidence;
                secretsJson = everySecret;
                nixbotApi = true;
                status = 0;
                argv = [
                  "event"
                  "--upload"
                ];
                env = r2Env;
              }
              {
                name = "registry: browser-evidence buildFinished without an R2 secret fails before the program runs";
                kind = "buildFinished";
                entry = registry.browser-evidence;
                secretsJson = cloudflareAccount // forge;
                status = 1;
                expect = [ "error: R2_EVIDENCE_ACCESS_KEY_ID missing from $HERCULES_CI_SECRETS_JSON" ];
              }
              {
                name = "registry: browser-evidence pullRequest uploads with the R2 secrets and nixbot's API token, without --rev";
                kind = "pullRequest";
                entry = registry.browser-evidence;
                secretsJson = everySecret;
                nixbotApi = true;
                status = 0;
                argv = [
                  "event"
                  "--upload"
                ];
                env = r2Env;
              }
              {
                name = "registry: browser-evidence pullRequest without an R2 secret fails before the program runs";
                kind = "pullRequest";
                entry = registry.browser-evidence;
                secretsJson = cloudflareAccount // forge;
                status = 1;
                expect = [ "error: R2_EVIDENCE_ACCESS_KEY_ID missing from $HERCULES_CI_SECRETS_JSON" ];
              }
              {
                name = "registry: browser-evidence main appends --rev and receives the R2 secrets and nixbot's API token";
                kind = "main";
                entry = registry.browser-evidence;
                claims = mainClaims;
                secretsJson = everySecret;
                nixbotApi = true;
                status = 0;
                expect = [ "CI-RUN-CONTEXT: branch=main is_main=true" ];
                argv = [
                  "main"
                  "--upload"
                  "--rev"
                  rev
                ];
                env = r2Env;
              }
            ]}

            touch $out
          '';
    };
}
