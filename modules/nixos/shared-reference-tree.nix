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
      handlerConfig = pkgs.writeText "ghq-writer.json" (
        builtins.toJSON {
          inherit (cfg) root allowedProtocols;
          group = cfg.writer;
        }
      );
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

        systemd.tmpfiles.rules = [ "d ${cfg.root} 0750 ${cfg.writer} ${cfg.writer} -" ];

        home-manager.users = lib.genAttrs cfg.participants (_: {
          programs.ghq-shared.root = cfg.root;
        });

        systemd.sockets.ghq-writer = {
          description = "Request socket of the shared ghq tree's writer";
          wantedBy = [ "sockets.target" ];
          socketConfig = {
            ListenStream = pkgs.ghq-shared.socket;
            SocketUser = "root";
            SocketGroup = cfg.writer;
            SocketMode = "0660";
            Accept = true;
          };
        };

        systemd.services."ghq-writer@" = {
          description = "Carry out one request against the shared ghq tree";
          serviceConfig = {
            User = cfg.writer;
            Group = cfg.writer;
            UMask = "0027";
            ExecStart = "${pkgs.ghq-shared}/libexec/ghq-shared/ghq-writer-handler ${handlerConfig}";
            StandardInput = "socket";
            StandardOutput = "socket";
            StandardError = "journal";
            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectHome = true;
            ProtectSystem = "strict";
            ReadWritePaths = [ cfg.root ];
          };
        };
      };
    };
}
