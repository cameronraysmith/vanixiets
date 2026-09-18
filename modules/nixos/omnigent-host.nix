{ config, inputs, ... }:
let
  flakeConfig = config;
in
{
  flake.modules.nixos.omnigent-host =
    {
      config,
      lib,
      pkgs,
      utils,
      options,
      ...
    }:
    let
      cfg = config.services.omnigent-host;
      adminUsers = lib.filter (
        name:
        let
          user = config.users.users.${name} or { };
        in
        (user.isNormalUser or false) && lib.elem "wheel" (user.extraGroups or [ ])
      ) (lib.attrNames (config.home-manager.users or { }));
      userHome = config.users.users.${cfg.user}.home;
      hostEnvironment = cfg.environment // {
        HOME = userHome;
      };
      workers = cfg.workers;
      enabledWorkers = lib.filterAttrs (_: worker: worker.enable) workers;
      account = worker: config.users.users.${worker.user};
      homeFor = worker: (account worker).home;
      deliveries = lib.mapAttrs (
        _: worker:
        flakeConfig.flake.lib.mkOmnigentWorkerCredentials {
          inherit pkgs worker;
          osConfig = config;
          home = homeFor worker;
          group = (account worker).group;
          serverUrl = cfg.serverUrl;
        }
      ) workers;
      credentialDeliveries = lib.filterAttrs (_: delivery: delivery.enabled) deliveries;
      secretDependencies =
        name:
        lib.optional (
          deliveries.${name}.enabled && (config.sops.useSystemdActivation or false)
        ) "sops-install-secrets.service";
      groupsFor =
        worker:
        lib.unique (
          [ (account worker).group ]
          ++ (account worker).extraGroups
          ++ lib.attrNames (
            lib.filterAttrs (_: group: lib.elem worker.user group.members) config.users.groups
          )
        );
      matchesUser =
        worker: entry:
        entry == "*"
        || entry == worker.user
        || (lib.hasPrefix "@" entry && lib.elem (lib.removePrefix "@" entry) (groupsFor worker));
      privilegedGroups = [
        "root"
        "wheel"
        "sudo"
        "admin"
        "docker"
        "lxd"
        "incus-admin"
        "libvirtd"
        "kvm"
        "disk"
        "shadow"
        "nixbld"
      ];
      reservedEnvironment = flakeConfig.flake.lib.omnigentReservedEnvironment { isDarwin = false; };
      hmUnit = worker: "home-manager-${utils.escapeSystemdPath worker.user}.service";
      workerEnvironment =
        worker:
        worker.environment
        // {
          HOME = homeFor worker;
          USER = worker.user;
          LOGNAME = worker.user;
          SHELL = utils.toShellPath (account worker).shell;
          XDG_CONFIG_HOME = "${homeFor worker}/.config";
          XDG_CACHE_HOME = "${homeFor worker}/.cache";
          XDG_DATA_HOME = "${homeFor worker}/.local/share";
          XDG_STATE_HOME = "${homeFor worker}/.local/state";
          PI_ACP_PI_COMMAND = "atomic";
          PI_CODING_AGENT_DIR = "${homeFor worker}/.atomic/agent";
          OMNIGENT_RUNNER_ENV_PASSTHROUGH = "PI_ACP_PI_COMMAND,PI_CODING_AGENT_DIR";
          PATH = lib.mkForce (
            inputs.self.lib.omnigentWorkerPath {
              inherit pkgs;
              home = config.home-manager.users.${worker.user};
              inherit (worker) extraPackages;
            }
          );
        };
    in
    {
      imports = [ flakeConfig.flake.modules.nixos.omnigent-worker-options ];
      options.services.omnigent-host = {
        enable = lib.mkEnableOption "the foreground Omnigent host";
        package = lib.mkPackageOption pkgs "omnigent" { };
        serverUrl = lib.mkOption {
          type = lib.types.str;
          description = "HTTPS URL of the Omnigent server.";
        };
        user = lib.mkOption {
          type = lib.types.str;
          default =
            if lib.length adminUsers == 1 then
              lib.head adminUsers
            else
              throw "Set services.omnigent-host.user explicitly: Omnigent requires a unique normal wheel user with a Home Manager configuration for automatic selection";
          defaultText = lib.literalMD "The unique normal wheel user with a Home Manager configuration.";
          description = "Existing Unix account holding runner and vendor credentials; set explicitly when automatic selection is ambiguous.";
        };
        hostName = lib.mkOption {
          type = lib.types.str;
          default = config.networking.hostName;
          description = "Fleet name for the unit description and operator-seeded host.name in ~/.omnigent/config.yaml.";
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
          systemd.services.omnigent-host = {
            description = "Omnigent host ${cfg.hostName}";
            wantedBy = [ "multi-user.target" ];
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];
            path = inputs.self.lib.omnigentRuntimePackages pkgs ++ cfg.extraPackages;
            environment = hostEnvironment;
            serviceConfig = {
              Type = "simple";
              Environment = lib.mapAttrsToList (name: value: builtins.toJSON "${name}=${value}") hostEnvironment;
              ExecStart = lib.escapeShellArgs [
                (lib.getExe cfg.package)
                "host"
                "--server"
                cfg.serverUrl
              ];
              User = cfg.user;
              WorkingDirectory = userHome;
              Restart = "on-failure";
              RestartSec = 5;
              MemoryHigh = "6G";
              MemoryMax = "8G";
              NoNewPrivileges = true;
            };
          };
        })
        (lib.mkIf (workers != { }) {
          assertions = [
            {
              assertion = !config.home-manager.startAsUserService;
              message = "Omnigent workers require integrated system Home Manager activation.";
            }
            {
              assertion =
                lib.length (lib.unique (map (w: w.user) (lib.attrValues workers)))
                == lib.length (lib.attrNames workers);
              message = "Omnigent workers require distinct accounts.";
            }
          ]
          ++ lib.concatMap (delivery: delivery.assertions) (lib.attrValues credentialDeliveries)
          ++ lib.concatLists (
            lib.mapAttrsToList (name: worker: [
              {
                assertion = builtins.match "[a-z0-9][a-z0-9-]*" name != null;
                message = "Omnigent worker ${name}: invalid instance name.";
              }
              {
                assertion =
                  worker.user != "root"
                  && (account worker).uid != 0
                  && (account worker).isNormalUser
                  && lib.all (
                    other:
                    other.name == worker.user || (account worker).uid == null || other.uid != (account worker).uid
                  ) (lib.attrValues config.users.users);
                message = "Omnigent worker ${name}: requires a dedicated non-root normal account.";
              }
              {
                assertion =
                  (account worker).createHome
                  && lib.elem (account worker).homeMode [
                    "700"
                    "0700"
                  ]
                  && lib.hasPrefix "/" (homeFor worker)
                  && homeFor worker != "/"
                  && lib.all (part: part != ".." && part != ".") (lib.splitString "/" (homeFor worker))
                  && lib.all (other: other.name == worker.user || other.home != homeFor worker) (
                    lib.attrValues config.users.users
                  )
                  && lib.hasPrefix "${homeFor worker}/" worker.workspaceRoot
                  && lib.all (part: part != ".." && part != ".") (lib.splitString "/" worker.workspaceRoot);
                message = "Omnigent worker ${name}: requires a private distinct home and home-local workspace.";
              }
              {
                assertion =
                  lib.intersectLists privilegedGroups (groupsFor worker) == [ ]
                  && !lib.any (
                    rule:
                    lib.any (
                      selector:
                      if lib.isInt selector then
                        (account worker).uid != null && selector == (account worker).uid
                      else
                        selector == "ALL" || selector == worker.user
                    ) rule.users
                    || lib.any (
                      selector:
                      lib.any (
                        group:
                        if lib.isInt selector then
                          let
                            gid = config.users.groups.${group}.gid or null;
                          in
                          gid != null && selector == gid
                        else
                          selector == group
                      ) (groupsFor worker)
                    ) rule.groups
                  ) config.security.sudo.extraRules;
                message = "Omnigent worker ${name}: administrative groups or sudo grants are prohibited.";
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
                assertion = !(builtins.hasAttr worker.user (config.hm-sops-bridge.users or { }));
                message = "Omnigent worker ${name}: personal age-bridge enrollment is prohibited.";
              }
              {
                assertion =
                  config.home-manager.users.${worker.user}.programs.omnigent.workerCredentials
                  == (if deliveries.${name}.enabled then deliveries.${name}.policy else null);
                message = "Omnigent worker ${name}: Home Manager credential paths must match the host adapter's allow-list.";
              }
            ]) workers
          );

          home-manager.users = lib.listToAttrs (
            lib.mapAttrsToList (
              name: worker:
              lib.nameValuePair worker.user (
                { lib, ... }: {
                  imports = [
                    flakeConfig.flake.modules.homeManager.omnigent-worker
                    deliveries.${name}.homeModule
                  ]
                  ++ worker.extraHomeModules;
                  home.stateVersion = lib.mkDefault config.system.stateVersion;
                  programs.omnigent = {
                    package = cfg.package;
                    settings.host.name = worker.hostName;
                  };
                  programs.direnv.config.whitelist.prefix = lib.mkIf worker.autoApproveDirenv [
                    worker.workspaceRoot
                  ];
                  home.activation.omnigentWorkspace = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
                    run ${pkgs.coreutils}/bin/install -d -m 0700 ${lib.escapeShellArg worker.workspaceRoot}
                  '';
                  home.activation.omnigentCredentialReadiness = lib.mkIf deliveries.${name}.enabled (
                    lib.hm.dag.entryBefore [ "writeBoundary" ] deliveries.${name}.readiness
                  );
                }
              )
            ) workers
          );

          systemd.services = lib.mkMerge [
            (lib.listToAttrs (
              lib.mapAttrsToList (
                name: worker:
                lib.nameValuePair (lib.removeSuffix ".service" (hmUnit worker)) {
                  serviceConfig.UMask = "0077";
                  serviceConfig.NoNewPrivileges = true;
                  after = secretDependencies name;
                  requires = secretDependencies name;
                }
              ) workers
            ))
            (lib.mapAttrs' (
              name: worker:
              lib.nameValuePair "omnigent-host-${name}" {
                description = "Omnigent host ${worker.hostName} (${worker.owner})";
                wantedBy = [ "multi-user.target" ];
                after = [
                  "network-online.target"
                  (hmUnit worker)
                ]
                ++ secretDependencies name;
                wants = [ "network-online.target" ];
                requires = [ (hmUnit worker) ] ++ secretDependencies name;
                restartTriggers = [ config.home-manager.users.${worker.user}.home.activationPackage ];
                environment = workerEnvironment worker;
                serviceConfig = {
                  Type = "simple";
                  User = worker.user;
                  Group = (account worker).group;
                  WorkingDirectory = homeFor worker;
                  UMask = "0077";
                  NoNewPrivileges = true;
                  Restart = "on-failure";
                  RestartSec = 5;
                  MemoryHigh = "6G";
                  MemoryMax = "8G";
                  UnsetEnvironment = [
                    "SSH_AUTH_SOCK"
                    "SSH_AGENT_PID"
                    "ATOMIC_CODING_AGENT_DIR"
                    "OMP_CODING_AGENT_DIR"
                  ];
                  ExecStartPre = pkgs.writeShellScript "omnigent-${name}-private-home" ''
                    set -eu
                    test "$(${pkgs.coreutils}/bin/stat -c %u "$HOME")" = "$(${pkgs.coreutils}/bin/id -u)"
                    test "$(${pkgs.coreutils}/bin/stat -c %a "$HOME")" = 700
                    ${lib.optionalString deliveries.${name}.enabled deliveries.${name}.readiness}
                  '';
                  ExecStart = lib.escapeShellArgs [
                    (lib.getExe cfg.package)
                    "host"
                    "--server"
                    cfg.serverUrl
                  ];
                };
              }
            ) enabledWorkers)
          ];
        })
        (lib.optionalAttrs (options ? clan.core.vars) (
          lib.mkIf (credentialDeliveries != { }) {
            clan.core.vars.generators = lib.mkMerge (
              map (delivery: delivery.generators) (lib.attrValues credentialDeliveries)
            );
            sops.templates = lib.mkMerge (
              map (delivery: delivery.templates) (lib.attrValues credentialDeliveries)
            );
          }
        ))
      ];
    };
}
