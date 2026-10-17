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
        assertions = [
          {
            assertion = cfg.writerId != null;
            message = "shared-reference-tree: darwin requires an operator-approved services.shared-reference-tree.writerId.";
          }
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
          StandardErrorPath = "/var/log/ghq-writer.log";
        };

        home-manager.users = lib.genAttrs humanParticipants (_: {
          programs.ghq-shared.root = cfg.root;
        });

        # The root's parent is root-owned, so only an administrator can have put
        # something at the root before the writer existed. An empty directory is
        # taken over; anything else the writer does not already own stops
        # activation rather than trusting entries another account controls.
        system.activationScripts.postActivation.text = lib.mkBefore ''
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
