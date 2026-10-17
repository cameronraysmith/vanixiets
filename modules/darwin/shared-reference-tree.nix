{ config, ... }:
let
  flakeConfig = config;
in
{
  flake.modules.darwin.shared-reference-tree =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.shared-reference-tree;
      # Darwin Omnigent workers have standalone Home Manager configurations built
      # by the omnigent-host adapter, which sets their root itself.
      workerUsers = map (worker: worker.user) (
        lib.attrValues (config.services.omnigent-host.workers or { })
      );
      humanParticipants = lib.subtractLists workerUsers cfg.participants;
      label = "org.vanixiets.ghq-writer";
      # launchd opens StandardErrorPath as UserName before spawning the handler,
      # so the writer must own the directory it lands in; /var/log is root's.
      logDir = "/var/log/ghq-writer";
      handlerConfig = pkgs.writeText "ghq-writer.json" (
        builtins.toJSON {
          inherit (cfg) root allowedProtocols;
          group = cfg.writer;
        }
      );
    in
    {
      imports = [ flakeConfig.flake.modules.darwin.shared-reference-tree-options ];

      config = lib.mkIf cfg.enable {
        assertions =
          let
            hm = config.home-manager.users;
            writer = config.users.users.${cfg.writer};
            sorted = lib.sort lib.lessThan;
            safeDirectories = user: lib.toList (hm.${user}.programs.git.settings.safe.directory or [ ]);
            conforms =
              user:
              flakeConfig.flake.lib.sharedReferenceTreeSafeDirectoriesConform {
                roots = cfg.rootForms;
                participant = lib.elem user cfg.participants;
              } (safeDirectories user);
            provision = "/usr/bin/install -d -m 0750 -o ${cfg.writer} -g ${cfg.writer} \"$ghqRoot\"";
            # Everything activation runs before it first touches this daemon's plist;
            # without that reference the ordering checks below would hold vacuously.
            daemonSplit = lib.splitString "/LaunchDaemons/${label}.plist" config.system.activationScripts.script.text;
            daemonLoaded = builtins.length daemonSplit > 1;
            beforeDaemon = lib.head daemonSplit;
          in
          [
            {
              assertion = cfg.writerId != null;
              message = "shared-reference-tree: darwin requires an operator-approved services.shared-reference-tree.writerId.";
            }
            {
              assertion = sorted config.users.groups.${cfg.writer}.members == sorted cfg.participants;
              message = "shared-reference-tree: group ${cfg.writer} members must equal the declared participants.";
            }
            {
              assertion =
                writer.shell == "/usr/bin/false"
                && writer.openssh.authorizedKeys.keys == [ ]
                && writer.openssh.authorizedKeys.keyFiles == [ ]
                && !(lib.elem cfg.writer config.nix.settings.trusted-users)
                && !(lib.hasInfix cfg.writer (config.security.sudo.extraConfig or ""));
              message = "shared-reference-tree: the writer ${cfg.writer} must have no login shell, keys, sudo rule or Nix trust.";
            }
            {
              assertion = lib.all conforms (lib.attrNames hm);
              message = "shared-reference-tree: each participant's safe.directory must be exactly ${cfg.root}/*, and no account's may be * or enclose ${cfg.root}.";
            }
            {
              assertion = lib.all (
                user: (hm.${user}.programs.git.settings.safe.bareRepository or null) == "explicit"
              ) humanParticipants;
              message = "shared-reference-tree: every participant's safe.bareRepository must be explicit.";
            }
            {
              assertion = lib.all (
                user: (hm.${user}.programs.ghq-shared.root or null) == cfg.root
              ) humanParticipants;
              message = "shared-reference-tree: every participant's programs.ghq-shared.root must be ${cfg.root}.";
            }
            {
              assertion = daemonLoaded && lib.hasInfix provision beforeDaemon;
              message = "shared-reference-tree: ${cfg.root} must be provisioned mode 0750, owned by ${cfg.writer}, before activation loads ${label}.";
            }
            {
              assertion =
                let
                  plist = config.environment.launchDaemons."${label}.plist".text;
                  stderrPath = lib.head (
                    builtins.match ".*<key>StandardErrorPath</key>[[:space:]]*<string>([^<]*)</string>.*" plist
                  );
                in
                daemonLoaded
                && lib.hasInfix "/usr/bin/install -d -m 0750 -o ${cfg.writer} -g ${cfg.writer} ${dirOf stderrPath}" beforeDaemon;
              message = "shared-reference-tree: the writer daemon's StandardErrorPath must lie in a directory provisioned for ${cfg.writer} before activation loads ${label}.";
            }
          ];

        # git resolves safe.directory entries and repository paths through
        # symlinks, and /var is a symlink to /private/var.
        services.shared-reference-tree.rootForms = [
          cfg.root
          "/private/var/lib/ghq"
        ];

        users.users.${cfg.writer} = {
          uid = cfg.writerId;
          gid = cfg.writerId;
          home = cfg.root;
          createHome = false;
          shell = "/usr/bin/false";
          isHidden = true;
          description = "Sole writer of the shared ghq reference tree";
        };
        users.groups.${cfg.writer} = {
          gid = cfg.writerId;
          members = cfg.participants;
          description = "Readers of the shared ghq reference tree";
        };
        users.knownUsers = [ cfg.writer ];
        users.knownGroups = [ cfg.writer ];

        # Written as a raw plist because nix-darwin's typed Sockets submodule has no
        # SockPathOwner or SockPathGroup, which keep the socket root:_ghq 0660.
        environment.launchDaemons."${label}.plist".text = lib.generators.toPlist { escape = true; } {
          Label = label;
          ProgramArguments = [
            "${pkgs.ghq-shared}/libexec/ghq-shared/ghq-writer-handler"
            "${handlerConfig}"
          ];
          inetdCompatibility.Wait = false;
          Sockets.Listener = {
            SockPathName = pkgs.ghq-shared.socket;
            SockPathOwner = 0;
            SockPathGroup = cfg.writerId;
            SockPathMode = 432; # 0660; plists have no octal literals
          };
          UserName = cfg.writer;
          GroupName = cfg.writer;
          Umask = 23; # 0027
          StandardErrorPath = "${logDir}/writer.log";
        };

        system.newsyslog = {
          enable = true;
          # N: no daemon to signal; launchd reopens the log for each connection's handler.
          files.ghq-writer = [
            {
              logfilename = "${logDir}/writer.log";
              owner = cfg.writer;
              group = cfg.writer;
              mode = "640";
              count = 5;
              size = "1024";
              flags = [
                "N"
                "Z"
              ];
            }
          ];
        };

        home-manager.users = lib.genAttrs humanParticipants (_: {
          programs.ghq-shared.root = cfg.root;
        });

        # Runs ahead of launchd loading the writer daemon. The root's parent is
        # root-owned, so only an administrator can have put something at the root
        # before the writer existed. An empty directory is taken over; anything
        # else the writer does not already own stops activation rather than
        # trusting entries another account controls.
        system.activationScripts.launchd.text = lib.mkBefore ''
          /usr/bin/install -d -m 0750 -o ${cfg.writer} -g ${cfg.writer} ${logDir}
          ghqRoot=${lib.escapeShellArg cfg.root}
          if [ -L "$ghqRoot" ] || { [ -e "$ghqRoot" ] && [ ! -d "$ghqRoot" ]; }; then
            echo "shared-reference-tree: $ghqRoot exists and is not a directory; refusing to provision it" >&2
            exit 1
          elif [ ! -e "$ghqRoot" ]; then
            /usr/bin/install -d -m 0750 -o ${cfg.writer} -g ${cfg.writer} "$ghqRoot"
          elif [ "$(/usr/bin/stat -f %Su "$ghqRoot")" != ${cfg.writer} ] && [ -n "$(/bin/ls -A "$ghqRoot")" ]; then
            echo "shared-reference-tree: $ghqRoot is not empty and not owned by ${cfg.writer}; refusing to adopt it" >&2
            exit 1
          else
            /usr/sbin/chown ${cfg.writer}:${cfg.writer} "$ghqRoot"
            /bin/chmod 0750 "$ghqRoot"
          fi
        '';
      };
    };
}
