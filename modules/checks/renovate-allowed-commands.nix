# Every postUpgradeTasks command that .github/renovate.json asks Renovate to
# run must match one of flake.lib.renovateSettings.allowedCommands, the
# allowlist the renovate aspect gives the instance on magnetite. Renovate
# turns a refused command into an artifact error and still pushes the branch
# (execute-post-upgrade-commands.ts:222-229; update/branch/index.ts:480-500),
# so drift here would ship incomplete commits. An empty command set fails too,
# so the check cannot pass vacuously.
#
# Renovate matches the compiled command (openspec automate-package-version-bumps
# design D8), so a templated command is rendered with the `name`, `version` and
# `rev` of every pkgs/by-name/*/pin.json before matching, and fails when no pin
# exists to render it with. Each templated command rendered with the version
# `1.0.0;id` must be refused.
#
# Renovate commits a postUpgradeTasks write only when the file matches the
# task's fileFilters (execute-post-upgrade-commands.ts) and drops the rest
# silently, so the pin rule's fileFilters must cover every path the realizer
# may write (design D5): each pin's pkgs/by-name/<name>/pin.json and each
# companion `path`, apmRef and fixedOutputHash alike. The paths are matched
# with Renovate's own minimatch wrapper and options, `{ dot: true }`, and the
# check fails naming every pin and path left uncovered.
#
# The check reads static flake data and repository files only; it evaluates no
# host configuration and no package. Matching uses jq's Oniguruma `test`; the
# patterns use only anchors, literals, an escaped dot, bracket classes and `*`,
# on which Oniguruma and JavaScript regexes agree.
{ config, lib, ... }:
{
  perSystem =
    { system, pkgs, ... }:
    lib.mkIf (system == "x86_64-linux") {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # nixbot: 1 run, too few to class (design D4)
        renovate-allowed-commands = {
          class = "medium";
          measured = false;
        };
      };
      checks.renovate-allowed-commands =
        let
          inherit (config.flake.lib) renovateSettings;
          byName = ../../pkgs/by-name;
          pinFiles = lib.filter builtins.pathExists (
            map (name: byName + "/${name}/pin.json") (
              lib.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir byName))
            )
          );
          input = pkgs.writeText "renovate-allowed-commands-input.json" (
            builtins.toJSON {
              allowed = renovateSettings.allowedCommands;
              repoRules = (lib.importJSON ../../.github/renovate.json).packageRules or [ ];
              pins = map (
                file:
                let
                  pin = lib.importJSON file;
                in
                {
                  inherit (pin) name version;
                  rev = pin.rev or null;
                  companions = map (companion: companion.path) (pin.companions or [ ]);
                }
              ) pinFiles;
            }
          );
          # The wrapper resolves minimatch from Renovate's own node_modules, so
          # the glob semantics are those of the Renovate the instance runs.
          fileFiltersScript = pkgs.writeText "renovate-pin-file-filters.mjs" ''
            import { readFileSync } from "node:fs";
            import { minimatch } from "${pkgs.renovate}/lib/node_modules/renovate/dist/util/minimatch.js";

            const fail = (message) => {
              process.stderr.write("renovate-allowed-commands: " + message + "\n");
              process.exit(1);
            };
            const input = JSON.parse(readFileSync(process.argv[2], "utf8"));
            const pinRules = input.repoRules.filter(
              (rule) => (rule.matchManagers ?? []).includes("custom.jsonata") && rule.postUpgradeTasks,
            );
            if (pinRules.length !== 1) {
              fail("expected exactly one custom.jsonata rule with postUpgradeTasks, found " + pinRules.length);
            }
            // Renovate's default when fileFilters is absent.
            const filters = pinRules[0].postUpgradeTasks.fileFilters ?? ["**/*"];
            const paths = input.pins.flatMap((pin) =>
              ["pkgs/by-name/" + pin.name + "/pin.json", ...pin.companions].map((path) => [pin.name, path]),
            );
            const uncovered = paths.filter(
              ([, path]) => !filters.some((pattern) => minimatch(pattern, { dot: true }).match(path)),
            );
            if (uncovered.length > 0) {
              fail(
                "realizer writes not matched by the pin rule's postUpgradeTasks.fileFilters, which Renovate would drop:\n" +
                  uncovered.map(([name, path]) => "  " + name + ": " + path).join("\n"),
              );
            }
            console.log(
              "OK: " + paths.length + " realizer write paths of " + input.pins.length + " pins matched by the pin rule's fileFilters",
            );
          '';
        in
        pkgs.runCommand "renovate-allowed-commands"
          {
            nativeBuildInputs = [
              pkgs.jq
              pkgs.nodejs
            ];
            passthru.meta.description = "Every Renovate postUpgradeTasks command, rendered with every package pin, matches the instance's allowedCommands, and the pin rule's fileFilters cover every realizer write";
          }
          ''
            jq -n -r --slurpfile in ${input} '
              def admitted: . as $c | any($in[0].allowed[]; . as $re | $c | test($re));
              def render($name; $version; $digest):
                split("{{{depName}}}") | join($name)
                | split("{{{newVersion}}}") | join($version)
                | split("{{{newDigest}}}") | join($digest);
              ($in[0].pins) as $pins
              | [ $in[0].repoRules[]
                  | .postUpgradeTasks.commands // [] | .[] ] as $cmds
              | [ $cmds[] | select(contains("{{")) ] as $templated
              | ([ $cmds[] | select(contains("{{") | not) ]
                 + [ $templated[] as $t | $pins[] as $p | $t | render($p.name; $p.version; $p.rev // "") ]) as $rendered
              | [ $templated[] as $t | $pins[] as $p | $t | render($p.name; "1.0.0;id"; "1.0.0;id") ] as $negatives
              | if ($cmds | length) == 0 then
                  "renovate-allowed-commands: no postUpgradeTasks command found; the check would be vacuous" | halt_error(1)
                elif ($templated | length) > 0 and ($pins | length) == 0 then
                  ("renovate-allowed-commands: no pin.json to render " + ($templated | unique | join(", ")) + " with; the check would be vacuous\n") | halt_error(1)
                else
                  ([ $rendered[] | select(contains("{{")) ] | unique) as $unrendered
                  | ([ $rendered[] | select(admitted | not) ] | unique) as $refused
                  | ([ $negatives[] | select(admitted) ] | unique) as $leaked
                  | if ($unrendered | length) > 0 then
                      ("renovate-allowed-commands: template variable left unrendered in: " + ($unrendered | join(", ")) + "\n") | halt_error(1)
                    elif ($refused | length) > 0 then
                      ("renovate-allowed-commands: not admitted by allowedCommands: " + ($refused | join(", ")) + "\n") | halt_error(1)
                    elif ($leaked | length) > 0 then
                      ("renovate-allowed-commands: admitted with the version 1.0.0;id: " + ($leaked | join(", ")) + "\n") | halt_error(1)
                    else
                      "OK: \($rendered | unique | length) distinct rendered task commands admitted, \($negatives | length) renderings with 1.0.0;id refused"
                    end
                end'
            node ${fileFiltersScript} ${input}
            touch $out
          '';
    };
}
