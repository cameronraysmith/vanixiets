# vanixiets herculesCI effects as data, and the one interpreter that runs them.
#
# An effect carries no behaviour of its own: each entry names a program whose
# behaviour a rehearsal check exercises, and the only code between nixbot and
# that program is the script rendered here, which checks.effects-interpreter
# runs. An entry declares what every run shares (program, rehearsals) and,
# per trigger, how that run is invoked and which secrets it holds:
#
#   main              herculesCI.onPush.default.outputs.effects.<name>
#   pullRequest       herculesCI.onEvent.pull_request.<name>
#   pullRequestClosed herculesCI.onEvent.pull_request_closed.<name>
#   buildFinished     herculesCI.onEvent.build_finished.<name>
#
# nixbot evaluates onEvent from the default branch whatever pull request the
# event is about, delivers pull_request once a pull request head built green
# and pull_request_closed on close or merge of any pull request it built
# (Mic92/nixbot docs/EFFECTS.md "Events"; nixbot/nixbot/service.py:271-311).
#
# build_finished covers any finished build, not just successful main builds.
# Its effect code comes from the default branch; event data and build artifacts
# remain untrusted. At nixbot 2626aa2, `when` is scheduler delivery metadata,
# not a shell guard. Branch/status filters select builds, not authorized actors.
# Credentialed buildFinished requires write/admin permission; missing actors
# (including poll-originated builds without an actor) fail closed in nixbot's
# matcher. A PR author's permission can also satisfy that matcher.
#
# The rendered script, in order: for main, the effectRunContext guard that
# ends any run that is not a push to main before a secret is read; exports
# each secret the trigger declares from $HERCULES_CI_SECRETS_JSON, failing on
# the first one absent, null or empty; then execs the program with the
# trigger's arguments, and for main `--rev <rev>`.
#
# nixbot enforces hercules-ci secretsMap semantics: only the destinations named
# in the map are written into $HERCULES_CI_SECRETS_JSON, and mkEffect declares
# an empty map when none is given, which grants nothing. The map is therefore
# derived from each trigger's `secrets` and `forgeToken`, so a run can read
# exactly what its trigger declares and never another trigger's secrets: a
# pull request run of a program whose main run holds a write credential
# receives none of it.
#
# Rehearsals are effect inputs that nothing runs: nixbot builds the inputs of
# every onPush and onEvent effect on pull requests and merge-queue batches
# without running them, which makes each rehearsal part of the pre-merge
# nixbot/effects gate.
{
  config,
  inputs,
  lib,
  withSystem,
  ...
}:
let
  inherit (lib) types;

  runContext = config.flake.lib.effectRunContext;
  secretNames = builtins.attrNames config.flake.lib.vanixietsEffectSecrets;

  triggerModule = {
    options = {
      args = lib.mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Literal arguments passed to the program.";
      };
      lock = lib.mkOption {
        type = types.str;
        description = ''
          nixbot lock name; runs sharing one are serialised across builds and
          trigger kinds. `{pr}` expands to the pull request number.
        '';
      };
      secrets = lib.mkOption {
        type = types.listOf (types.enum secretNames);
        default = [ ];
        description = "flake.lib.vanixietsEffectSecrets entries exported to this run's environment.";
      };
      forgeToken = lib.mkOption {
        type = types.bool;
        default = false;
        description = "Export nixbot's forge token for this run as GITHUB_FORGE_TOKEN.";
      };
    };
  };

  triggerOption =
    description:
    lib.mkOption {
      type = types.nullOr (types.submodule triggerModule);
      default = null;
      inherit description;
    };

  finishedTriggerModule = {
    imports = [ triggerModule ];
    options.when = lib.mkOption {
      default = { };
      description = "nixbot build_finished delivery conditions; enforced by the scheduler, not the effect shell.";
      type = types.submodule {
        options = {
          permission = lib.mkOption {
            type = types.nullOr (
              types.enum [
                "read"
                "write"
                "admin"
              ]
            );
            default = null;
            description = "Minimum actor or PR author permission. Credentialed runs require write or admin; an absent actor/author does not qualify.";
          };
          branches = lib.mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "Branch globs selecting builds, not an authorization boundary.";
          };
          status = lib.mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "Build statuses selecting deliveries, not an authorization boundary.";
          };
          transition = lib.mkOption {
            type = types.nullOr (
              types.enum [
                "broke"
                "fixed"
              ]
            );
            default = null;
            description = "Build status transition required for delivery.";
          };
        };
      };
    };
  };

  entryModule = {
    options = {
      program = lib.mkOption {
        type = types.pathInStore;
        description = "Executable the effect execs, normally a flake app's program.";
      };
      rehearsals = lib.mkOption {
        type = types.nonEmptyListOf types.package;
        description = "Checks exercising the program; built by the pre-merge gate.";
      };
      triggers = {
        main = triggerOption "Run on nixbot's onPush for main, behind the main-only guard, with `--rev <rev>` appended.";
        pullRequest = triggerOption "Run as a nixbot onEvent pull_request effect.";
        pullRequestClosed = triggerOption "Run as a nixbot onEvent pull_request_closed effect.";
        buildFinished = lib.mkOption {
          type = types.nullOr (types.submodule finishedTriggerModule);
          default = null;
          description = "Run as a nixbot onEvent build_finished effect, without the main-only guard or appended revision.";
        };
      };
    };
  };

  # Pure, so checks.effects-interpreter renders its synthetic entries with the
  # function the interpreter uses. `kind` is a `triggers` attribute name.
  renderEffectScript =
    { rev }:
    kind: entry:
    let
      trigger = entry.triggers.${kind};
      main = kind == "main";
      argv =
        trigger.args
        ++ lib.optionals main [
          "--rev"
          rev
        ];
      exportSecret = name: path: ''
        if ! ${name}="$(jq -er ${lib.escapeShellArg "${path} | select(type == \"string\" and . != \"\")"} "$HERCULES_CI_SECRETS_JSON")"; then
          echo "error: ${name} missing from \$HERCULES_CI_SECRETS_JSON" >&2
          exit 1
        fi
        export ${name}
      '';
    in
    ''
      set -euo pipefail
      ${lib.optionalString main runContext.mainOnlyGuard}
      ${lib.concatMapStrings (name: exportSecret name ".${name}.data.value") trigger.secrets}
      ${lib.optionalString trigger.forgeToken (
        exportSecret "GITHUB_FORGE_TOKEN" ".GITHUB_FORGE_TOKEN.data.token"
      )}
      exec ${lib.escapeShellArgs ([ entry.program ] ++ argv)}
    '';

  # Pure, so checks.effects-interpreter pins the map every registry trigger
  # receives with the function mkEffect uses.
  secretsMapFor =
    trigger:
    lib.genAttrs trigger.secrets lib.id
    // lib.optionalAttrs trigger.forgeToken { GITHUB_FORGE_TOKEN.type = "GitToken"; };

  mkEffect =
    kind: rev: name: entry:
    let
      trigger = entry.triggers.${kind};
      main = kind == "main";
    in
    withSystem "x86_64-linux" (
      { pkgs, ... }:
      (inputs.hercules-ci-effects.lib.withPkgs pkgs).mkEffect (
        {
          inherit name;
          inherit (trigger) lock;
          inputs = [
            pkgs.jq
          ]
          ++ lib.optionals main [
            pkgs.coreutils
            pkgs.curl
          ]
          ++ entry.rehearsals;
          secretsMap = secretsMapFor trigger;
          effectScript = renderEffectScript { inherit rev; } kind entry;
        }
        // lib.optionalAttrs (kind == "buildFinished") {
          passthru.when = lib.filterAttrs (_: value: value != null && value != [ ]) trigger.when;
        }
        // lib.optionalAttrs main {
          # Declaring an audience is what makes nixbot expose the identity
          # endpoint the guard reads. A JSON-array string: a nix list would
          # serialise space-separated, which nixbot rejects.
          idTokenAudiences = builtins.toJSON [ runContext.audience ];
        }
      )
    );

  effectsFor =
    kind: rev:
    lib.mapAttrs (mkEffect kind rev) (
      lib.filterAttrs (_: entry: entry.triggers.${kind} != null) config.vanixiets.effects
    );

  requireTrigger =
    name: entry:
    let
      finished = entry.triggers.buildFinished;
    in
    if
      finished != null
      && (finished.secrets != [ ] || finished.forgeToken)
      && !(builtins.elem finished.when.permission [
        "write"
        "admin"
      ])
    then
      throw "vanixiets.effects.${name}: credentialed triggers.buildFinished requires when.permission = write or admin; branch/status filters are not authorization"
    else if lib.any (trigger: trigger != null) (builtins.attrValues entry.triggers) then
      entry
    else
      throw "vanixiets.effects.${name}: declares no trigger; set at least one of triggers.{main,pullRequest,pullRequestClosed,buildFinished}";
in
{
  options.vanixiets.effects = lib.mkOption {
    type = types.attrsOf (types.submodule entryModule);
    default = { };
    apply = lib.mapAttrs requireTrigger;
    description = "vanixiets herculesCI effects, interpreted into herculesCI outputs.";
  };

  config = {
    flake.lib.vanixietsEffectScript = renderEffectScript;
    flake.lib.vanixietsEffectSecretsMap = secretsMapFor;

    herculesCI = herculesCI: {
      onPush.default.outputs.effects = effectsFor "main" herculesCI.config.repo.rev;
      onEvent.pull_request = effectsFor "pullRequest" null;
      onEvent.pull_request_closed = effectsFor "pullRequestClosed" null;
      onEvent.build_finished = effectsFor "buildFinished" null;
    };
  };
}
