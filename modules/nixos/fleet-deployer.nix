# The fleet deployer (openspec change delegate-fleet-deploys, design D1-D13):
# a system account on flake.lib.fleetDeployer.deployerHost (cinnabar) that
# agent sessions reach over SSH with their request key, whose only command is
# fleet-deploy-request.
#
# - Its age and SSH keys are generated here on first start by
#   fleet-deployer-keys (UMask 0277, so files are 0400 in a 0700 directory)
#   and never leave the host; only their public halves are committed, to
#   flake.lib.fleetDeployer.keys and sops/users/fleet-deployer (D2).
# - fleet-deployer-keycheck fails, daily and at start, when the keys' modes,
#   owner or public halves differ from what the flake declares (D12, Q8).
# - fleet-deploy-notify, started by a path unit on requests.jsonl, posts one
#   message per request to the fleet-deploy topic with the alerter token,
#   which stays root-only; the request command never holds it (D12). ntfy's
#   `alerter:fleet-*:rw` (modules/machines/nixos/cinnabar/ntfy.nix) admits
#   the topic.
#
# flake.lib.fleetDeployer.failures, asserted by modules/checks/machines.nix,
# holds the account's authorized keys to the requesters' forced-command
# lines and the key directory to its declared mode.
{ config, inputs, ... }:
let
  d = config.flake.lib.fleetDeployer;
  secretsModule = config.flake.modules.nixos.secrets;
in
{
  flake.modules.nixos.fleet-deployer =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.fleet-deployer;
      inherit (d) account;
      stateDir = cfg.requestConfig.stateDir;
      keyDir = "${stateDir}/keys";
      clan = inputs.clan-core.packages.${pkgs.stdenv.hostPlatform.system}.default;
      requestConfig = pkgs.writeText "fleet-deploy-config.json" (builtins.toJSON cfg.requestConfig);
      request = pkgs.symlinkJoin {
        name = "fleet-deploy-request-${account}";
        paths = [ pkgs.fleet-deploy-request ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/fleet-deploy-request \
            --prefix PATH : ${lib.makeBinPath [ clan ]} \
            --set FLEET_DEPLOY_CONFIG ${requestConfig}
        '';
      };
      sshConfig = pkgs.writeText "fleet-deployer-ssh-config" ''
        Host *
          IdentityFile ${keyDir}/id_ed25519
          IdentitiesOnly yes
          ForwardAgent no
          BatchMode yes
      '';
      declared = lib.optionalAttrs (cfg.keys != null) cfg.keys;
      keycheck = pkgs.writeShellApplication {
        name = "fleet-deployer-keycheck";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.age
          pkgs.openssh
        ];
        text = ''
          fail=0
          check() {
            local path=$1 mode=$2
            local actual
            actual=$(stat -c '%a %U %G' "$path")
            if [ "$actual" != "$mode ${account} ${account}" ]; then
              echo "$path is '$actual', expected '$mode ${account} ${account}'"
              fail=1
            fi
          }
          check ${keyDir} 700
          check ${keyDir}/age.key 400
          check ${keyDir}/id_ed25519 400
          ${lib.optionalString (declared ? age) ''
            if [ "$(age-keygen -y ${keyDir}/age.key)" != ${lib.escapeShellArg declared.age} ]; then
              echo "age.key's public key differs from flake.lib.fleetDeployer.keys.age"
              fail=1
            fi
          ''}
          ${lib.optionalString (declared ? ssh) ''
            if [ "$(ssh-keygen -y -f ${keyDir}/id_ed25519 | cut -d' ' -f1-2)" != ${lib.escapeShellArg (lib.concatStringsSep " " (lib.take 2 (lib.splitString " " declared.ssh)))} ]; then
              echo "id_ed25519's public key differs from flake.lib.fleetDeployer.keys.ssh"
              fail=1
            fi
          ''}
          exit "$fail"
        '';
      };
      notify = pkgs.writeShellApplication {
        name = "fleet-deploy-notify";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.jq
          cfg.ntfySend
        ];
        text = ''
          log=${stateDir}/requests.jsonl
          offset_file=/var/lib/fleet-deploy-notify/offset
          [ -e "$log" ] || exit 0
          # A write while this runs does not restart it, so read until the
          # offset reaches the file's size.
          while :; do
            offset=$(cat "$offset_file" 2>/dev/null || echo 0)
            size=$(stat -c %s "$log")
            [ "$size" -lt "$offset" ] && offset=0
            [ "$size" -eq "$offset" ] && break
            tail -c +"$((offset + 1))" "$log" | head -c "$((size - offset))" |
              while IFS= read -r line; do
                outcome=$(jq -r .outcome <<<"$line")
                message=$(jq -r -f ${pkgs.fleet-deploy-request}/share/fleet-deploy-request/notice.jq <<<"$line")
                case "$outcome" in
                  refused | unhealthy | rolled-back | unconfirmed) ntfy-send "$message" fleet-deploy -H "Priority: high" ;;
                  *) ntfy-send "$message" fleet-deploy ;;
                esac
              done
            echo "$size" >"$offset_file"
          done
        '';
      };
    in
    {
      imports = [ secretsModule ];

      # Defaults are the fleet's; vmTests.x86_64-linux.fleet-deployer replaces
      # them with a local forge, cache, stubs and a test requester.
      options.services.fleet-deployer = {
        requestConfig = lib.mkOption {
          type = lib.types.attrs;
          default = d.requestConfig;
          defaultText = lib.literalExpression "flake.lib.fleetDeployer.requestConfig";
          description = "What fleet-deploy-request reads (FLEET_DEPLOY_CONFIG).";
        };
        requesterLines = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = d.requesterLines;
          defaultText = lib.literalExpression "flake.lib.fleetDeployer.requesterLines";
          description = "The deployer account's authorized keys, one forced-command line per requester.";
        };
        ntfySend = lib.mkOption {
          type = lib.types.package;
          default = pkgs.ntfy-send;
          defaultText = lib.literalExpression "pkgs.ntfy-send";
          description = "The ntfy client fleet-deploy-notify posts with.";
        };
        notifyTokenFile = lib.mkOption {
          type = lib.types.str;
          default = config.vanixiets.secrets.ntfy-alerter.files.token.path;
          defaultText = lib.literalExpression "the ntfy-alerter token's path";
          description = "The alerter token fleet-deploy-notify posts with; root-only.";
        };
        keys = lib.mkOption {
          type = lib.types.nullOr (lib.types.attrsOf lib.types.str);
          default = d.keys;
          defaultText = lib.literalExpression "flake.lib.fleetDeployer.keys";
          description = "The public halves fleet-deployer-keycheck compares the generated keys with; null checks modes only.";
        };
      };

      config = {
        users.users.${account} = {
          isSystemUser = true;
          group = account;
          home = stateDir;
          createHome = false;
          shell = pkgs.bashInteractive;
          openssh.authorizedKeys.keys = cfg.requesterLines;
        };
        users.groups.${account} = { };

        environment.systemPackages = [ request ];

        systemd.tmpfiles.rules = [
          "d ${stateDir} 0700 ${account} ${account} -"
          "d ${keyDir} ${d.keyDirMode} ${account} ${account} -"
          "d ${stateDir}/.ssh 0700 ${account} ${account} -"
          "L+ ${stateDir}/.ssh/config - - - - ${sshConfig}"
          "d ${cfg.requestConfig.runDir} 0700 ${account} ${account} -"
          "d /var/lib/fleet-deploy-notify 0700 root root -"
        ];

        systemd.services.fleet-deployer-keys = {
          description = "Generate the fleet deployer's age and SSH keys once";
          wantedBy = [ "multi-user.target" ];
          after = [ "systemd-tmpfiles-setup.service" ];
          path = [
            pkgs.age
            pkgs.openssh
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = account;
            Group = account;
            UMask = d.keyUMask;
          };
          script = ''
            [ -e ${keyDir}/age.key ] || age-keygen -o ${keyDir}/age.key
            [ -e ${keyDir}/id_ed25519 ] || ssh-keygen -q -t ed25519 -N "" -C ${account}@${config.networking.hostName} -f ${keyDir}/id_ed25519
            # ssh-keygen sets 0600 on the private key itself, past the UMask.
            chmod 0400 ${keyDir}/age.key ${keyDir}/id_ed25519
          '';
        };

        systemd.services.fleet-deployer-keycheck = {
          description = "Check the fleet deployer's keys are private and match the flake";
          wantedBy = [ "multi-user.target" ];
          after = [ "fleet-deployer-keys.service" ];
          requires = [ "fleet-deployer-keys.service" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = lib.getExe keycheck;
          };
        };
        systemd.timers.fleet-deployer-keycheck = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            Persistent = true;
            # observability-notify requires a named zone on notified units' timers.
            OnCalendar = "*-*-* 04:00:00 UTC";
          };
        };

        systemd.paths.fleet-deploy-notify = {
          wantedBy = [ "paths.target" ];
          pathConfig.PathChanged = "${stateDir}/requests.jsonl";
        };
        systemd.services.fleet-deploy-notify = {
          description = "Post fleet deploy requests to the fleet-deploy topic";
          # Every request line restarts it; the default start limit (5 in 10 s)
          # would stop the path unit during a burst of refusals.
          startLimitIntervalSec = 0;
          environment.NTFY_TOKEN_FILE = cfg.notifyTokenFile;
          serviceConfig = {
            Type = "oneshot";
            ExecStart = lib.getExe notify;
          };
        };
      };
    };
}
