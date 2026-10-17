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
      };
    };
}
