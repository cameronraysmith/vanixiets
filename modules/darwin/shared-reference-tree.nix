{ config, ... }:
let
  flakeConfig = config;
in
{
  flake.modules.darwin.shared-reference-tree =
    { config, lib, ... }:
    let
      cfg = config.services.shared-reference-tree;
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

        # /Users/Shared is world-writable with the sticky bit, so any account could
        # have created the root first. An empty directory is taken over; anything
        # else that the writer does not already own stops activation rather than
        # trusting entries another account controls.
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
