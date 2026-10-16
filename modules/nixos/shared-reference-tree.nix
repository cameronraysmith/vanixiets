{ config, ... }:
let
  flakeConfig = config;
in
{
  flake.modules.nixos.shared-reference-tree =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.shared-reference-tree;
    in
    {
      imports = [ flakeConfig.flake.modules.nixos.shared-reference-tree-options ];

      config = lib.mkIf cfg.enable {
        users.users.${cfg.writer} = {
          isSystemUser = true;
          group = cfg.writer;
          home = cfg.root;
          createHome = false;
          shell = "${pkgs.shadow}/bin/nologin";
          hashedPassword = "!";
          description = "Sole writer of the shared ghq reference tree";
        };
        users.groups.${cfg.writer}.members = cfg.participants;
      };
    };
}
