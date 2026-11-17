# Every postUpgradeTasks command that .github/renovate.json, or the Phase 1
# global packageRules in flake.lib.renovateSettings, asks Renovate to run must
# match one of flake.lib.renovateSettings.allowedCommands, the allowlist the
# renovate aspect gives the instance on magnetite. Renovate turns a refused
# command into an artifact error and still pushes the branch
# (execute-post-upgrade-commands.ts:222-229; update/branch/index.ts:480-500),
# so drift here would ship incomplete commits. An empty command set fails too,
# so the check cannot pass vacuously.
#
# The check reads static flake data and the repository file only; it evaluates
# no host configuration. Matching uses jq's Oniguruma `test`; the patterns use
# only anchors, literals and an escaped dot, on which Oniguruma and JavaScript
# regexes agree.
{ config, lib, ... }:
{
  perSystem =
    { system, pkgs, ... }:
    lib.mkIf (system == "x86_64-linux") {
      checks.renovate-allowed-commands =
        let
          inherit (config.flake.lib) renovateSettings;
          input = pkgs.writeText "renovate-allowed-commands-input.json" (
            builtins.toJSON {
              allowed = renovateSettings.allowedCommands;
              globalRules = renovateSettings.phase1PackageRules or [ ];
              repoRules = (lib.importJSON ../../.github/renovate.json).packageRules or [ ];
            }
          );
        in
        pkgs.runCommand "renovate-allowed-commands"
          {
            nativeBuildInputs = [ pkgs.jq ];
            passthru.meta.description = "Every Renovate postUpgradeTasks command matches the instance's allowedCommands";
          }
          ''
            jq -n -r --slurpfile in ${input} '
              ($in[0].allowed) as $allowed
              | [ ($in[0].repoRules + $in[0].globalRules)[]
                  | .postUpgradeTasks.commands // [] | .[] ] as $cmds
              | if ($cmds | length) == 0 then
                  "renovate-allowed-commands: no postUpgradeTasks command found; the check would be vacuous" | halt_error(1)
                else
                  [ $cmds[] | select(. as $c | any($allowed[]; . as $re | $c | test($re)) | not) ] | unique
                  | if length > 0 then
                      ("renovate-allowed-commands: not admitted by allowedCommands: " + join(", ") + "\n") | halt_error(1)
                    else "OK: \($cmds | unique | length) distinct task commands admitted" end
                end'
            touch $out
          '';
    };
}
