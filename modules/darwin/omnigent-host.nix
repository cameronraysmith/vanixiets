{ config, inputs, ... }:
let
  flakeConfig = config;
in
{
  flake.modules.darwin.omnigent-host =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.omnigent-host;
      userHome = config.users.users.${cfg.user}.home;
      logDirectory = "${userHome}/.omnigent/logs/host";
      explicitPath =
        lib.makeBinPath (inputs.self.lib.omnigentRuntimePackages pkgs ++ cfg.extraPackages)
        + ":/usr/bin:/bin:/usr/sbin:/sbin";
      workers = cfg.workers;
      enabledWorkers = lib.filterAttrs (_: worker: worker.enable) workers;
      account = worker: config.users.users.${worker.user};
      homeFor = worker: toString (account worker).home;
      groupsFor =
        worker:
        lib.attrNames (
          lib.filterAttrs (
            _: group: group.gid == (account worker).gid || lib.elem worker.user group.members
          ) config.users.groups
        );
      matchesUser =
        worker: entry:
        entry == "*"
        || entry == worker.user
        || (lib.hasPrefix "@" entry && lib.elem (lib.removePrefix "@" entry) (groupsFor worker));
      reservedEnvironment =
        name:
        lib.elem name [
          "HOME"
          "USER"
          "LOGNAME"
          "PATH"
          "SHELL"
          "SSH_AUTH_SOCK"
          "SSH_AGENT_PID"
          "GIT_CONFIG_GLOBAL"
          "GIT_CONFIG_SYSTEM"
          "GIT_CONFIG_COUNT"
          "BASH_ENV"
          "ENV"
          "SKIP_SANITY_CHECKS"
          "DRY_RUN"
        ]
        || lib.any (prefix: lib.hasPrefix prefix name) [
          "XDG_"
          "NIX_"
          "OMNIGENT_"
          "PI_"
          "ATOMIC_"
          "OMP_"
          "CLAUDE_"
          "CODEX_"
          "GH_"
          "LINEAR_"
          "LD_"
          "DYLD_"
        ];
      workerHomes = lib.mapAttrs (
        _: worker:
        inputs.home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = {
            flake = inputs.self;
            osConfig = null;
          };
          modules = [
            flakeConfig.flake.modules.homeManager.omnigent-worker
            ({ lib, ... }: {
              home = {
                username = worker.user;
                uid = (account worker).uid;
                homeDirectory = homeFor worker;
                stateVersion = lib.mkDefault "25.11";
                activation.omnigentWorkspace = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
                  run ${pkgs.coreutils}/bin/install -d -m 0700 ${lib.escapeShellArg worker.workspaceRoot}
                '';
              };
              programs.omnigent = {
                package = cfg.package;
                settings.host.name = worker.hostName;
              };
              programs.direnv.config.whitelist.prefix = lib.mkIf worker.autoApproveDirenv [
                worker.workspaceRoot
              ];
              # HM otherwise performs LaunchAgent reconciliation even with launchd.enable=false.
              launchd.enable = false;
              home.activation.setupLaunchAgents = lib.mkForce (lib.hm.dag.entryAfter [ "writeBoundary" ] "");
              targets.darwin.copyApps.enable = false;
              targets.darwin.linkApps.enable = false;
            })
          ]
          ++ worker.extraHomeModules;
        }
      ) workers;
      workerEnvironment =
        name: worker:
        worker.environment
        // {
          HOME = homeFor worker;
          USER = worker.user;
          LOGNAME = worker.user;
          SHELL = "${pkgs.bash}/bin/bash";
          XDG_CONFIG_HOME = "${homeFor worker}/.config";
          XDG_CACHE_HOME = "${homeFor worker}/.cache";
          XDG_DATA_HOME = "${homeFor worker}/.local/share";
          XDG_STATE_HOME = "${homeFor worker}/.local/state";
          PI_ACP_PI_COMMAND = "atomic";
          PI_CODING_AGENT_DIR = "${homeFor worker}/.atomic/agent";
          OMNIGENT_RUNNER_ENV_PASSTHROUGH = "PI_ACP_PI_COMMAND,PI_CODING_AGENT_DIR";
          PATH =
            (inputs.self.lib.omnigentWorkerPath {
              inherit pkgs;
              home = workerHomes.${name}.config;
              inherit (worker) extraPackages;
            })
            + ":/usr/bin:/bin:/usr/sbin:/sbin";
        };
      prepareHome = pkgs.writeShellScript "omnigent-prepare-darwin-home" ''
        set -eu
        user="$1" uid="$2" gid="$3" home="$4"
        test "$(${pkgs.coreutils}/bin/id -u "$user")" = "$uid"
        test "$(${pkgs.coreutils}/bin/id -g "$user")" = "$gid"
        for directory in "$home" "$home/.omnigent" "$home/.omnigent/logs" "$home/.omnigent/logs/host"; do
          test ! -L "$directory"
          if test -e "$directory"; then
            test -d "$directory"
            test "$(${pkgs.coreutils}/bin/stat -c %u "$directory")" = "$uid"
            ${pkgs.coreutils}/bin/chmod 0700 "$directory"
          else
            ${pkgs.coreutils}/bin/install -d -m 0700 -o "$uid" -g "$gid" "$directory"
          fi
        done
      '';
      launcher =
        name: worker:
        pkgs.writeShellScript "omnigent-${name}-start" ''
          set -eu
          umask 077
          unset SSH_AUTH_SOCK SSH_AGENT_PID ATOMIC_CODING_AGENT_DIR OMP_CODING_AGENT_DIR
          test "$(${pkgs.coreutils}/bin/id -u)" = "$(${pkgs.coreutils}/bin/id -u ${lib.escapeShellArg worker.user})"
          for directory in "$HOME" "$HOME/.omnigent" "$HOME/.omnigent/logs" "$HOME/.omnigent/logs/host"; do
            test ! -L "$directory"
            test "$(${pkgs.coreutils}/bin/stat -c %u "$directory")" = "$(${pkgs.coreutils}/bin/id -u)"
            test "$(${pkgs.coreutils}/bin/stat -c %a "$directory")" = 700
          done
          ${workerHomes.${name}.activationPackage}/activate
          exec ${
            lib.escapeShellArgs [
              (lib.getExe cfg.package)
              "host"
              "--server"
              cfg.serverUrl
            ]
          }
        '';
    in
    {
      imports = [ flakeConfig.flake.modules.darwin.omnigent-worker-options ];
      options.services.omnigent-host = {
        enable = lib.mkEnableOption "the foreground Omnigent host";
        package = lib.mkPackageOption pkgs "omnigent" { };
        serverUrl = lib.mkOption {
          type = lib.types.str;
          description = "HTTPS URL of the Omnigent server.";
        };
        user = lib.mkOption {
          type = lib.types.str;
          default = config.system.primaryUser;
          description = "Existing Home Manager account holding runner and vendor credentials.";
        };
        hostName = lib.mkOption {
          type = lib.types.str;
          default = config.networking.hostName;
          description = "Fleet name merged into host.name in ~/.omnigent/config.yaml.";
        };
        extraPackages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
          description = "Additional packages on the host and runner PATH.";
        };
        environment = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          description = "Non-secret environment values forwarded to the foreground host.";
        };
      };

      config = lib.mkMerge [
        (lib.mkIf cfg.enable {
          assertions = [
            {
              assertion =
                config.system.primaryUser != null
                && config.system.primaryUser != ""
                && builtins.hasAttr config.system.primaryUser config.users.users;
              message = "Omnigent requires a configured primary user.";
            }
            {
              assertion = cfg.user != "" && builtins.hasAttr cfg.user config.users.users;
              message = "Omnigent requires an existing selected account.";
            }
            {
              assertion =
                builtins.hasAttr cfg.user config.home-manager.users
                && config.home-manager.users.${cfg.user}.home.username == cfg.user
                && config.home-manager.users.${cfg.user}.home.homeDirectory == userHome;
              message = "Omnigent requires a Home Manager user matching the selected account and home.";
            }
          ];

          home-manager.users.${cfg.user} =
            { lib, ... }:
            {
              programs.omnigent = {
                enable = true;
                package = cfg.package;
                settings.host.name = cfg.hostName;
              };

              home.activation.omnigentHostLogDirectory =
                lib.hm.dag.entryBetween
                  [ "setupLaunchAgents" ]
                  [
                    "writeBoundary"
                    "omnigentMergeConfig"
                  ]
                  ''
                    run ${pkgs.coreutils}/bin/install -d -m 0700 ${lib.escapeShellArg logDirectory}
                  '';

              launchd.agents.omnigent-host = {
                enable = true;
                domain = "user";
                waitForNixStore = true;
                config = {
                  ProgramArguments = [
                    (lib.getExe cfg.package)
                    "host"
                    "--server"
                    cfg.serverUrl
                  ];
                  EnvironmentVariables = cfg.environment // {
                    HOME = userHome;
                    PATH = explicitPath;
                  };
                  WorkingDirectory = userHome;
                  RunAtLoad = true;
                  KeepAlive.SuccessfulExit = false;
                  ThrottleInterval = 5;
                  ProcessType = "Standard";
                  StandardOutPath = "${logDirectory}/service.log";
                  StandardErrorPath = "${logDirectory}/service.log";
                };
              };
            };
        })
        (lib.mkIf (workers != { }) {
          assertions = [
            {
              assertion =
                lib.length (lib.unique (map (w: w.user) (lib.attrValues workers)))
                == lib.length (lib.attrNames workers);
              message = "Omnigent workers require distinct accounts.";
            }
          ]
          ++ lib.concatLists (
            lib.mapAttrsToList (name: worker: [
              {
                assertion = builtins.match "[a-z0-9][a-z0-9-]*" name != null;
                message = "Omnigent worker ${name}: invalid instance name.";
              }
              {
                assertion =
                  worker.user != "root"
                  && (account worker).name == worker.user
                  && (account worker).uid > 0
                  && worker.user != config.system.primaryUser
                  && lib.elem worker.user config.users.knownUsers
                  && lib.all (other: other.name == worker.user || other.uid != (account worker).uid) (
                    lib.attrValues config.users.users
                  );
                message = "Omnigent worker ${name}: requires a dedicated non-root managed account.";
              }
              {
                assertion =
                  (account worker).createHome
                  && (account worker).home != null
                  && lib.hasPrefix "/" (homeFor worker)
                  && homeFor worker != "/"
                  && homeFor worker != "/var/empty"
                  && lib.all (part: part != ".." && part != ".") (lib.splitString "/" (homeFor worker))
                  && lib.all (other: other.name == worker.user || other.home != (account worker).home) (
                    lib.attrValues config.users.users
                  )
                  && lib.hasPrefix "${homeFor worker}/" worker.workspaceRoot
                  && lib.all (part: part != ".." && part != ".") (lib.splitString "/" worker.workspaceRoot);
                message = "Omnigent worker ${name}: requires a distinct home and home-local workspace.";
              }
              {
                assertion =
                  !lib.elem (account worker).gid [
                    0
                    80
                  ]
                  && lib.intersectLists [ "root" "wheel" "admin" "sudo" "nixbld" "docker" ] (groupsFor worker) == [ ];
                message = "Omnigent worker ${name}: administrative groups are prohibited.";
              }
              {
                assertion = !lib.any (matchesUser worker) config.nix.settings.trusted-users;
                message = "Omnigent worker ${name}: Nix trusted-user authority is prohibited.";
              }
              {
                assertion = lib.any (matchesUser worker) config.nix.settings.allowed-users;
                message = "Omnigent worker ${name}: ordinary Nix daemon access is required.";
              }
              {
                assertion = lib.all (key: !reservedEnvironment key) (lib.attrNames worker.environment);
                message = "Omnigent worker ${name}: environment cannot override identity, state or authority selectors.";
              }
              {
                assertion = !(builtins.hasAttr worker.user (config.home-manager.users or { }));
                message = "Omnigent worker ${name}: standalone Home Manager must be the only activation owner.";
              }
              {
                assertion = lib.all (agent: !agent.enable) (
                  lib.attrValues workerHomes.${name}.config.launchd.agents
                );
                message = "Omnigent worker ${name}: worker Home Manager must not require a user launchd domain.";
              }
              {
                assertion =
                  !workerHomes.${name}.config.targets.darwin.copyApps.enable
                  && !workerHomes.${name}.config.targets.darwin.linkApps.enable;
                message = "Omnigent worker ${name}: worker Home Manager must not require desktop application activation.";
              }
            ]) workers
          );
          environment.etc = lib.mapAttrs' (
            name: _:
            lib.nameValuePair "omnigent/workers/${name}" {
              source = workerHomes.${name}.activationPackage;
            }
          ) workers;
          # launchd opens log files before invoking the worker's unprivileged launcher.
          system.activationScripts.launchd.text = lib.mkBefore (
            lib.concatStringsSep "\n" (
              lib.mapAttrsToList (
                _: worker:
                lib.escapeShellArgs [
                  "/usr/bin/sudo"
                  "-u"
                  worker.user
                  "--set-home"
                  "--"
                  (toString prepareHome)
                  worker.user
                  (toString (account worker).uid)
                  (toString (account worker).gid)
                  (homeFor worker)
                ]
              ) workers
            )
          );
          launchd.daemons = lib.mapAttrs' (
            name: worker:
            lib.nameValuePair "omnigent-host-${name}" {
              command = launcher name worker;
              environment = workerEnvironment name worker;
              serviceConfig = {
                UserName = worker.user;
                WorkingDirectory = homeFor worker;
                Umask = 63;
                RunAtLoad = true;
                KeepAlive.SuccessfulExit = false;
                ThrottleInterval = 5;
                ProcessType = "Standard";
                StandardOutPath = "${homeFor worker}/.omnigent/logs/host/service.log";
                StandardErrorPath = "${homeFor worker}/.omnigent/logs/host/service.log";
              };
            }
          ) enabledWorkers;
        })
      ];
    };
}
