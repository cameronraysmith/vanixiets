# checks.x86_64-linux.fleet-deploy-request: the forced command's parser and
# authorization (pkgs/by-name/fleet-deploy-request), run as built with
# `--parse <requester>` over SSH_ORIGINAL_COMMAND fixtures against a fixture
# configuration. Accepted forms exit 0; each mutant must be refused with
# status 3. Then the forced command itself runs refused requests against a
# fixture forge, with the resolve and cache steps stubbed, and each
# requests.jsonl record must keep every field known when it was refused (F79).
# Last, it deploys to a darwin fixture target played by sshCommand, which
# fails the confirmation in two of three runs (F84): a target still running
# the deployed closure is `unconfirmed` (9), never `rolled-back`; one back on
# the closure it ran before is `rolled-back` (8); a confirmed one is
# `deployed` (0). Every run arms the watcher through the target's own
# `fleet-deploy-watch --arm`, never a launchctl command built here.
# A target that answers no SSH ends unreachable (5) before the commit is
# evaluated: none of the resolve, cache and vars stand-ins may run (F83).
# The deploy path itself is exercised by vmTests.x86_64-linux.fleet-deployer.
{ lib, ... }:
{
  perSystem =
    {
      pkgs,
      self',
      system,
      ...
    }:
    let
      config = pkgs.writeText "fleet-deploy-fixture.json" (
        builtins.toJSON {
          targets = {
            alpha = {
              class = "nixos";
              deployUser = "root";
            };
            beta = {
              class = "darwin";
              deployUser = "op";
            };
          };
          requesters = {
            op = [
              "alpha"
              "beta"
            ];
            pat = [ "beta" ];
          };
        }
      );
      # The cache check refuses every closure, so a request ends there with
      # its commit and closure resolved.
      closure = "/nix/store/00000000000000000000000000000000-fixture";
      recordConfig = pkgs.writeText "fleet-deploy-record-fixture.json" (
        builtins.toJSON {
          targets.alpha = {
            class = "nixos";
            deployUser = "root";
            targetHost = "root@alpha";
          };
          requesters = {
            op = [ "alpha" ];
            pat = [ ];
          };
          machines = [ "alpha" ];
          slots = 1;
          lockWait = 0;
          probeTimeout = 1;
          cacheStore = "fixture-cache";
          resolveCommand = pkgs.writeShellScript "resolve" ''
            echo '{"closure": "${closure}", "targetHost": "root@alpha"}'
          '';
          cacheCheckCommand = pkgs.writeShellScript "cache-check" "exit 1";
          # alpha answers the probe that precedes evaluation (F83).
          sshCommand = pkgs.writeShellScript "fixture-ssh" "exit 0";
        }
      );
      records = [
        # description, requester, command, jq condition on its record and on
        # $notice, the record rendered by fleet-deploy-notify's notice.jq
        [
          "refused at the cache check keeps commit and closure"
          "op"
          "deploy alpha --session s-1"
          ''.outcome == "refused" and .commit == $head and .closure == "${closure}" and .machine == "alpha" and .session == "s-1" and $notice == "refused: op asked to deploy alpha at \($head) (session s-1): ${closure} is not in fixture-cache: CI has not built it"''
        ]
        [
          "refused at target validation keeps session"
          "op"
          "deploy gamma --session s-2"
          ''.outcome == "refused" and .session == "s-2" and .machine == null and $notice == "refused: op asked to deploy \"gamma\" at main (session s-2): \"gamma\" is not a deploy target"''
        ]
        [
          "refused for a disallowed target keeps session and machine"
          "pat"
          "deploy alpha --session s-3"
          ''.outcome == "refused" and .session == "s-3" and .machine == "alpha" and $notice == "refused: pat asked to deploy alpha at main (session s-3): pat may not deploy alpha"''
        ]
        [
          "a target with ';' and spaces is reported whole"
          "op"
          "deploy magnetite;touch /tmp/canary --session s-4"
          ''.outcome == "refused" and .session == "s-4" and .target == "magnetite;touch /tmp/canary" and .reason == "\"magnetite;touch /tmp/canary\" is not a deploy target" and $notice == "refused: op asked to deploy \"magnetite;touch /tmp/canary\" at main (session s-4): \"magnetite;touch /tmp/canary\" is not a deploy target"''
        ]
        [
          "a target with a command substitution is reported whole"
          "op"
          "deploy magnetite$(touch /tmp/canary)"
          ''.outcome == "refused" and .reason == "\"magnetite$(touch /tmp/canary)\" is not a deploy target" and $notice == "refused: op asked to deploy \"magnetite$(touch /tmp/canary)\" at main (session none): \"magnetite$(touch /tmp/canary)\" is not a deploy target"''
        ]
        [
          "a command outside printable ASCII is malformed"
          "op"
          "deploy alphé --session s-5"
          ''.outcome == "refused" and .reason == "malformed command" and .target == null and $notice == "refused: op asked to deploy ? at main (session none): malformed command"''
        ]
        [
          "a command with a control character is malformed"
          "op"
          "deploy al\tpha"
          ''.outcome == "refused" and .reason == "malformed command" and .target == null''
        ]
      ];
      # A darwin target played from $HOME/target: HOME is the state directory
      # in every step (private_environment). The confirmation's result is the
      # run's scenario; `rolls-back` also returns the target to its previous
      # closure, as its watcher would.
      previousClosure = "/nix/store/11111111111111111111111111111111-previous";
      deployedClosure = "/nix/store/22222222222222222222222222222222-deployed";
      targetStub = pkgs.writeShellScript "fixture-target" ''
        t=$HOME/target
        printf '%s\n' "$2" >>"$t/commands"
        case "$2" in
          true) exit 0 ;;
          "readlink -f /run/current-system") cat "$t/current" ;;
          *"touch /var/run/fleet-deploy/"*".confirmed")
            case $(cat "$t/scenario") in
              confirmed) exit 0 ;;
              rolls-back)
                cp "$t/previous" "$t/current"
                exit 1
                ;;
              *) exit 1 ;;
            esac
            ;;
          "tail -n 1 /var/log/deploy-record.jsonl") printf '{"closure": "%s"}\n' "$(cat "$t/current")" ;;
          "sudo launchctl list") echo "PID Status Label" ;;
          *) exit 0 ;;
        esac
      '';
      deployConfig = pkgs.writeText "fleet-deploy-deploy-fixture.json" (
        builtins.toJSON {
          targets.beta = {
            class = "darwin";
            deployUser = "op";
            targetHost = "op@beta";
          };
          requesters = {
            op = [ "beta" ];
            pat = [ ];
          };
          machines = [ "beta" ];
          slots = 1;
          lockWait = 0;
          probeTimeout = 1;
          settle = 0;
          confirmWindow = 0;
          rollbackGrace = 0;
          activationWait = 60;
          cacheStore = "fixture-cache";
          resolveCommand = pkgs.writeShellScript "resolve" ''
            echo '{"closure": "${deployedClosure}", "targetHost": "op@beta"}'
          '';
          varsCheckCommand = pkgs.writeShellScript "vars-check" "exit 0";
          deployCommand = pkgs.writeShellScript "deploy" ''echo "$4" >"$HOME/target/current"'';
          sshCommand = targetStub;
        }
      );
      # An asleep target (F83): every SSH attempt fails, and each evaluating
      # step records that it ran. The request must end unreachable (5) with
      # none of them run, i.e. before the commit is evaluated.
      unreachableConfig = pkgs.writeText "fleet-deploy-unreachable-fixture.json" (
        builtins.toJSON {
          targets.alpha = {
            class = "nixos";
            deployUser = "root";
            targetHost = "root@alpha";
          };
          requesters = {
            op = [ "alpha" ];
            pat = [ ];
          };
          machines = [ "alpha" ];
          slots = 1;
          lockWait = 0;
          probeTimeout = 1;
          cacheStore = "fixture-cache";
          resolveCommand = pkgs.writeShellScript "resolve" ''
            echo resolve >>"$HOME/evaluated"
            echo '{"closure": "${closure}", "targetHost": "root@alpha"}'
          '';
          cacheCheckCommand = pkgs.writeShellScript "cache-check" ''echo cache-check >>"$HOME/evaluated"'';
          varsCheckCommand = pkgs.writeShellScript "vars-check" ''echo vars-check >>"$HOME/evaluated"'';
          sshCommand = pkgs.writeShellScript "fixture-ssh-asleep" "exit 255";
        }
      );
      deploys = [
        # description, the target's scenario, expected status, jq condition
        # on the record
        [
          "a confirmed deploy is deployed"
          "confirmed"
          0
          ''.outcome == "deployed"''
        ]
        [
          "a failed confirmation on the deployed closure is not rolled back"
          "stays"
          9
          ''.outcome == "unconfirmed" and (.reason | contains("${deployedClosure}"))''
        ]
        [
          "a failed confirmation back on the previous closure is rolled back"
          "rolls-back"
          8
          ''.outcome == "rolled-back" and (.reason | contains("${previousClosure}"))''
        ]
      ];
      deployRun = case: ''
        t=$TMPDIR/deploy-state/target
        rm -rf "$t"
        mkdir -p "$t"
        echo ${previousClosure} >"$t/previous"
        cp "$t/previous" "$t/current"
        echo ${lib.elemAt case 1} >"$t/scenario"
        set +e
        SSH_ORIGINAL_COMMAND="deploy beta" fleet-deploy-request op >/dev/null
        status=$?
        line=$(tail -n 1 "$TMPDIR/deploy-state/requests.jsonl")
        jq -e ${lib.escapeShellArg (lib.elemAt case 3)} <<<"$line" >/dev/null
        holds=$?
        grep -qx 'sudo /run/current-system/sw/bin/fleet-deploy-watch --arm [0-9a-f]\{12\} 60 0' "$t/commands"
        armed=$?
        set -e
        if [ "$status" != ${toString (lib.elemAt case 2)} ] || [ "$holds" != 0 ] || [ "$armed" != 0 ]; then
          echo "deploy "${lib.escapeShellArg (lib.elemAt case 0)}": status $status, record $line, target commands: $(tr '\n' ';' <"$t/commands")"
          failed=1
        fi
      '';
      notice = "${self'.packages.fleet-deploy-request}/share/fleet-deploy-request/notice.jq";
      record = case: ''
        set +e
        SSH_ORIGINAL_COMMAND=${lib.escapeShellArg (lib.elemAt case 2)} \
          fleet-deploy-request ${lib.elemAt case 1} >/dev/null
        status=$?
        line=$(tail -n 1 "$TMPDIR/state/requests.jsonl")
        notice=$(jq -r -f ${notice} <<<"$line")
        jq -e --arg head "$head" --arg notice "$notice" ${lib.escapeShellArg (lib.elemAt case 3)} <<<"$line" >/dev/null
        holds=$?
        set -e
        if [ "$status" != 3 ] || [ "$holds" != 0 ]; then
          echo "record "${lib.escapeShellArg (lib.elemAt case 0)}": status $status, record $line, notice $notice"
          failed=1
        fi
      '';
      cases = [
        # requester, command, expected status
        [
          "op"
          "deploy alpha"
          0
        ]
        [
          "op"
          "deploy beta 0123abc"
          0
        ]
        [
          "op"
          "deploy alpha 0123456789abcdef0123456789abcdef01234567 --session s-1.a_B"
          0
        ]
        [
          "pat"
          "deploy beta --session x"
          0
        ]
        [
          "op"
          ""
          3
        ]
        [
          "op"
          "deploy"
          3
        ]
        [
          "op"
          "deploy alpha; reboot"
          3
        ]
        [
          "op"
          "deploy alpha $(id)"
          3
        ]
        [
          "op"
          "deploy github:evil/flake#alpha"
          3
        ]
        [
          "op"
          "deploy alpha refs/heads/feature"
          3
        ]
        [
          "op"
          "deploy alpha 0123abc extra"
          3
        ]
        [
          "op"
          "deploy alpha  0123abc"
          3
        ]
        [
          "op"
          "deploy gamma"
          3
        ]
        [
          "op"
          "deploy stibnite"
          3
        ]
        [
          "pat"
          "deploy alpha"
          3
        ]
        [
          "nobody"
          "deploy alpha"
          3
        ]
        [
          "op"
          "deploy alpha 0123ABC"
          3
        ]
        [
          "op"
          "deploy alpha --session ${lib.fixedWidthString 65 "x" ""}"
          3
        ]
        [
          "op"
          "deploy alpha --session"
          3
        ]
        [
          "op"
          "shell"
          3
        ]
      ];
      run = case: ''
        set +e
        SSH_ORIGINAL_COMMAND=${lib.escapeShellArg (lib.elemAt case 1)} \
          fleet-deploy-request --parse ${lib.elemAt case 0} >/dev/null
        status=$?
        set -e
        if [ "$status" != ${toString (lib.elemAt case 2)} ]; then
          echo "case ${lib.escapeShellArg "${lib.elemAt case 0}: ${lib.elemAt case 1}"}: status $status, expected ${toString (lib.elemAt case 2)}"
          failed=1
        fi
      '';
    in
    lib.optionalAttrs (system == "x86_64-linux") {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # nixbot: 0 runs, too few to class (design D4)
        fleet-deploy-request = {
          class = "medium";
          measured = false;
        };
      };
      checks.fleet-deploy-request =
        pkgs.runCommand "fleet-deploy-request"
          {
            nativeBuildInputs = [
              self'.packages.fleet-deploy-request
              pkgs.git
              pkgs.jq
            ];
            FLEET_DEPLOY_CONFIG = config;
          }
          ''
            failed=0
            ${lib.concatMapStrings run cases}

            export HOME=$TMPDIR
            git init --quiet -b main "$TMPDIR/forge"
            git -C "$TMPDIR/forge" -c user.name=fixture -c user.email=fixture@localhost \
              commit --quiet --allow-empty -m fixture
            head=$(git -C "$TMPDIR/forge" rev-parse HEAD)
            mkdir "$TMPDIR/state"
            jq --arg tmp "$TMPDIR" \
              '.stateDir = $tmp + "/state" | .runDir = $tmp + "/run" | .forge = $tmp + "/forge"' \
              ${recordConfig} >"$TMPDIR/record-config.json"
            export FLEET_DEPLOY_CONFIG=$TMPDIR/record-config.json
            ${lib.concatMapStrings record records}

            mkdir "$TMPDIR/deploy-state"
            jq --arg tmp "$TMPDIR" \
              '.stateDir = $tmp + "/deploy-state" | .runDir = $tmp + "/deploy-run" | .forge = $tmp + "/forge"' \
              ${deployConfig} >"$TMPDIR/deploy-config.json"
            export FLEET_DEPLOY_CONFIG=$TMPDIR/deploy-config.json
            ${lib.concatMapStrings deployRun deploys}

            mkdir "$TMPDIR/asleep-state"
            jq --arg tmp "$TMPDIR" \
              '.stateDir = $tmp + "/asleep-state" | .runDir = $tmp + "/asleep-run" | .forge = $tmp + "/forge"' \
              ${unreachableConfig} >"$TMPDIR/asleep-config.json"
            set +e
            FLEET_DEPLOY_CONFIG=$TMPDIR/asleep-config.json SSH_ORIGINAL_COMMAND="deploy alpha" \
              fleet-deploy-request op >/dev/null
            status=$?
            set -e
            outcome=$(tail -n 1 "$TMPDIR/asleep-state/requests.jsonl" | jq -r .outcome)
            if [ "$status" != 5 ] || [ "$outcome" != unreachable ] || [ -e "$TMPDIR/asleep-state/evaluated" ]; then
              echo "asleep target: status $status, outcome $outcome, evaluated before the probe: $(tr '\n' ' ' <"$TMPDIR/asleep-state/evaluated" 2>/dev/null)"
              failed=1
            fi
            [ "$failed" = 0 ]
            touch $out
          '';
    };
}
