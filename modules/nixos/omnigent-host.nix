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
        let
          named = lib.unique (
            [ (account worker).group ]
            ++ (account worker).extraGroups
            ++ lib.attrNames (
              lib.filterAttrs (_: group: lib.elem worker.user group.members) config.users.groups
            )
          );
          gids = lib.filter (gid: gid != null) (map (name: config.users.groups.${name}.gid or null) named);
        in
        lib.unique (
          named
          ++ lib.attrNames (
            lib.filterAttrs (_: group: group.gid != null && lib.elem group.gid gids) config.users.groups
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
        "podman"
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
      rootlessPodman = worker: worker.containers.engine == "rootless-podman";
      restrictedIncus = worker: worker.containers.incus == "restricted";
      runtimeDirFor = worker: "/run/user/${toString (account worker).uid}";
      userManager = worker: "user@${toString (account worker).uid}.service";
      containerPackages =
        worker:
        lib.optionals (rootlessPodman worker) [
          config.virtualisation.podman.package
          # The real Docker CLI rather than podman's docker shim, which would
          # shadow a host's own Docker CLI and ignores DOCKER_HOST.
          pkgs.docker-client
          pkgs.docker-compose
        ]
        ++ lib.optional (restrictedIncus worker) config.virtualisation.incus.clientPackage;
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
          PATH = lib.mkForce (
            # NixOS's setuid wrappers (newuidmap/newgidmap among them) precede
            # everything as in NixOS's own PATH; under the unit's NoNewPrivileges
            # they run unprivileged, which is why the podman CLI goes remote below.
            lib.optionalString (rootlessPodman worker) "/run/wrappers/bin:"
            + inputs.self.lib.omnigentWorkerPath {
              inherit pkgs;
              home = config.home-manager.users.${worker.user};
              extraPackages = worker.extraPackages ++ containerPackages worker;
            }
          );
        }
        # Sessions are not logins, so nothing else supplies a runtime directory;
        # the lingering user manager creates it and socket-activates podman there.
        # Sessions inherit the unit's NoNewPrivileges, which voids the setuid
        # newuidmap a local podman CLI needs to create the user namespace, so
        # CONTAINER_HOST makes the podman CLI a client of the same socket.
        // lib.optionalAttrs (rootlessPodman worker) (
          let
            socket = "unix://${runtimeDirFor worker}/podman/podman.sock";
          in
          {
            XDG_RUNTIME_DIR = runtimeDirFor worker;
            DOCKER_HOST = socket;
            CONTAINER_HOST = socket;
            # omnigent's runner allowlist already carries XDG_RUNTIME_DIR but not
            # DOCKER_HOST or CONTAINER_HOST. Since omnigent 0.23.0 every generic ACP
            # child also inherits these names, so the list carries only stateless
            # locators; Atomic's state selectors are set by its own ACP command
            # (modules/home/ai/omnigent/acp.nix), never here.
            OMNIGENT_RUNNER_ENV_PASSTHROUGH = "DOCKER_HOST,CONTAINER_HOST";
          }
        );
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
        workerSliceMemoryMax = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "8G";
          description = ''
            When set, every worker unit runs in omnigent.slice and the slice
            carries this MemoryMax, so the workers share one ceiling instead of
            each holding its own. Each unit keeps its MemoryHigh and MemoryMax.
            Null leaves the units in system.slice.
          '';
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
              # omnigent exits 78 (EX_CONFIG) when its stored login has expired; only
              # `omnigent login` fixes that, so restarting just loops until it does.
              RestartPreventExitStatus = 78;
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
              {
                assertion = !rootlessPodman worker || (account worker).uid != null;
                message = "Omnigent worker ${name}: containers.engine \"rootless-podman\" requires users.users.${worker.user}.uid, which names its user manager and runtime directory; pin it before the worker is first created on a new host, or to the uid already allocated in /var/lib/nixos/uid-map.";
              }
              {
                assertion = !rootlessPodman worker || config.virtualisation.podman.enable;
                message = "Omnigent worker ${name}: containers.engine \"rootless-podman\" requires virtualisation.podman.enable, which installs the per-user podman.socket.";
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
                    { vcs.author = flakeConfig.flake.lib.vcsAuthor flakeConfig.flake.users.${worker.owner}.meta; }
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

          # Linger gives the worker a user manager, and with it /run/user/<uid> and
          # the socket-activated rootless podman API, without any login session.
          users.users = lib.mapAttrs' (_: worker: lib.nameValuePair worker.user { linger = true; }) (
            lib.filterAttrs (_: rootlessPodman) workers
          );

          # incus-user serves the incus group, confining each member to its own
          # restricted project; incus-admin stays out of reach.
          users.groups.incus = lib.mkIf (lib.any restrictedIncus (lib.attrValues workers)) {
            members = map (worker: worker.user) (lib.filter restrictedIncus (lib.attrValues workers));
          };

          systemd.slices = lib.mkIf (cfg.workerSliceMemoryMax != null) {
            omnigent = {
              description = "Omnigent workers";
              sliceConfig.MemoryMax = cfg.workerSliceMemoryMax;
            };
          };

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
                ++ secretDependencies name
                ++ lib.optional (rootlessPodman worker) (userManager worker);
                wants = [ "network-online.target" ] ++ lib.optional (rootlessPodman worker) (userManager worker);
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
                  # Exit 78 is an expired login; see the single-host unit above.
                  RestartPreventExitStatus = 78;
                  RestartSec = 5;
                  MemoryHigh = "6G";
                  MemoryMax = "8G";
                  Slice = lib.mkIf (cfg.workerSliceMemoryMax != null) "omnigent.slice";
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
