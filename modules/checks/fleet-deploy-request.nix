# checks.x86_64-linux.fleet-deploy-request: the forced command's parser and
# authorization (pkgs/by-name/fleet-deploy-request), run as built with
# `--parse <requester>` over SSH_ORIGINAL_COMMAND fixtures against a fixture
# configuration. Accepted forms exit 0; each mutant must be refused with
# status 3. Then the forced command itself runs refused requests against a
# fixture forge, with the resolve and cache steps stubbed, and each
# requests.jsonl record must keep every field known when it was refused (F79).
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
            [ "$failed" = 0 ]
            touch $out
          '';
    };
}
