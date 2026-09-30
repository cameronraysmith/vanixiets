# vanixiets herculesCI effects as data, and the one interpreter that runs them.
#
# An effect carries no behaviour of its own: each entry names a program whose
# behaviour a rehearsal check exercises, and the only code between nixbot and
# that program is the script rendered here, which checks.effects-interpreter
# runs. The rendered script, in order: for push-main entries, the
# effectRunContext guard that ends any run that is not a push to main before a
# secret is read; exports each declared secret from $HERCULES_CI_SECRETS_JSON,
# failing on the first one absent, null or empty; then execs the program.
#
# nixbot enforces hercules-ci secretsMap semantics: only the destinations named
# in the map are written into $HERCULES_CI_SECRETS_JSON, and mkEffect declares
# an empty map when none is given, which grants nothing. The map is therefore
# derived from each entry's `secrets`, so an effect can read exactly what it
# declares.
#
# Rehearsals are effect inputs that nothing runs: nixbot builds an effect's
# inputs on pull requests and merge-queue batches without running the effect,
# which makes each rehearsal part of the pre-merge nixbot/effects gate.
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

  entryModule = {
    options = {
      trigger = lib.mkOption {
        type = types.enum [
          "push-main"
          "pull-request"
        ];
        description = ''
          push-main runs on nixbot's onPush for main, behind the main-only
          guard, with `--rev <rev>` appended to the program's arguments.
          pull-request runs as a nixbot onEvent pull_request effect, which
          nixbot evaluates from the default branch.
        '';
      };
      program = lib.mkOption {
        type = types.pathInStore;
        description = "Executable the effect execs, normally a flake app's program.";
      };
      args = lib.mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Literal arguments passed to the program.";
      };
      secrets = lib.mkOption {
        type = types.listOf (types.enum secretNames);
        default = [ ];
        description = "flake.lib.vanixietsEffectSecrets entries exported to the program's environment.";
      };
      forgeToken = lib.mkOption {
        type = types.bool;
        default = false;
        description = "Export nixbot's forge token for this run as GITHUB_FORGE_TOKEN.";
      };
      rehearsals = lib.mkOption {
        type = types.nonEmptyListOf types.package;
        description = "Checks exercising the program; built by the pre-merge gate.";
      };
      lock = lib.mkOption {
        type = types.str;
        description = "nixbot lock name; runs sharing one are serialised across builds.";
      };
      permission = lib.mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "nixbot `when.permission` for pull-request entries.";
      };
    };
  };

  # Pure, so checks.effects-interpreter renders its synthetic entries with the
  # function the interpreter uses.
  renderEffectScript =
    { rev }:
    entry:
    let
      pushMain = entry.trigger == "push-main";
      argv =
        entry.args
        ++ lib.optionals pushMain [
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
      ${lib.optionalString pushMain runContext.mainOnlyGuard}
      ${lib.concatMapStrings (name: exportSecret name ".${name}.data.value") entry.secrets}
      ${lib.optionalString entry.forgeToken (
        exportSecret "GITHUB_FORGE_TOKEN" ".GITHUB_FORGE_TOKEN.data.token"
      )}
      exec ${lib.escapeShellArgs ([ entry.program ] ++ argv)}
    '';

  mkEffect =
    rev: name: entry:
    let
      pushMain = entry.trigger == "push-main";
    in
    lib.throwIf (pushMain && entry.permission != null)
      "vanixiets.effects.${name}: permission applies to pull-request entries only"
      (
        withSystem "x86_64-linux" (
          { pkgs, ... }:
          (inputs.hercules-ci-effects.lib.withPkgs pkgs).mkEffect (
            {
              inherit name;
              inherit (entry) lock;
              inputs = [
                pkgs.jq
              ]
              ++ lib.optionals pushMain [
                pkgs.coreutils
                pkgs.curl
              ]
              ++ entry.rehearsals;
              secretsMap =
                lib.genAttrs entry.secrets lib.id
                // lib.optionalAttrs entry.forgeToken { GITHUB_FORGE_TOKEN.type = "GitToken"; };
              effectScript = renderEffectScript { inherit rev; } entry;
            }
            // lib.optionalAttrs pushMain {
              # Declaring an audience is what makes nixbot expose the identity
              # endpoint the guard reads. A JSON-array string: a nix list would
              # serialise space-separated, which nixbot rejects.
              idTokenAudiences = builtins.toJSON [ runContext.audience ];
            }
            // lib.optionalAttrs (entry.permission != null) {
              # nixbot reads `when` off the effect value; passthru keeps it out
              # of the derivation environment.
              passthru.when.permission = entry.permission;
            }
          )
        )
      );

  entriesFor = trigger: lib.filterAttrs (_: entry: entry.trigger == trigger) config.vanixiets.effects;
in
{
  options.vanixiets.effects = lib.mkOption {
    type = types.attrsOf (types.submodule entryModule);
    default = { };
    description = "vanixiets herculesCI effects, interpreted into herculesCI outputs.";
  };

  config = {
    flake.lib.vanixietsEffectScript = renderEffectScript;

    herculesCI = herculesCI: {
      onPush.default.outputs.effects = lib.mapAttrs (mkEffect herculesCI.config.repo.rev) (
        entriesFor "push-main"
      );
      onEvent.pull_request = lib.mapAttrs (mkEffect null) (entriesFor "pull-request");
    };
  };
}
