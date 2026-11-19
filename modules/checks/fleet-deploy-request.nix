# checks.x86_64-linux.fleet-deploy-request: the forced command's parser and
# authorization (pkgs/by-name/fleet-deploy-request), run as built with
# `--parse <requester>` over SSH_ORIGINAL_COMMAND fixtures against a fixture
# configuration. Accepted forms exit 0; each mutant must be refused with
# status 3. The deploy path itself is exercised by
# vmTests.x86_64-linux.fleet-deployer.
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
            nativeBuildInputs = [ self'.packages.fleet-deploy-request ];
            FLEET_DEPLOY_CONFIG = config;
          }
          ''
            failed=0
            ${lib.concatMapStrings run cases}
            [ "$failed" = 0 ]
            touch $out
          '';
    };
}
