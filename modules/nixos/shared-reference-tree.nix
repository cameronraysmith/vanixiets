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
        assertions =
          let
            hm = config.home-manager.users;
            writer = config.users.users.${cfg.writer};
            sorted = lib.sort lib.lessThan;
            safeDirectories = user: lib.toList (hm.${user}.programs.git.settings.safe.directory or [ ]);
            rootRules = lib.filter (
              rule:
              let
                fields = lib.splitString " " rule;
              in
              builtins.length fields > 1 && builtins.elemAt fields 1 == cfg.root
            ) config.systemd.tmpfiles.rules;
          in
          [
            {
              assertion = sorted config.users.groups.${cfg.writer}.members == sorted cfg.participants;
              message = "shared-reference-tree: group ${cfg.writer} members must equal the declared participants.";
            }
            {
              assertion =
                writer.hashedPassword == "!"
                && writer.hashedPasswordFile == null
                && writer.extraGroups == [ ]
                && writer.openssh.authorizedKeys.keys == [ ]
                && writer.openssh.authorizedKeys.keyFiles == [ ]
                && lib.hasSuffix "/nologin" (toString writer.shell)
                && !(lib.elem cfg.writer config.nix.settings.trusted-users)
                && !(lib.any (rule: lib.elem cfg.writer (rule.users or [ ])) config.security.sudo.extraRules);
              message = "shared-reference-tree: the writer ${cfg.writer} must have no password, login shell, keys, extra groups, sudo rule or Nix trust.";
            }
            {
              assertion = lib.all (user: !(lib.elem "*" (safeDirectories user))) (lib.attrNames hm);
              message = "shared-reference-tree: no account may set safe.directory = *.";
            }
            {
              assertion = lib.all (
                user: (hm.${user}.programs.ghq-shared.root or null) == cfg.root
              ) cfg.participants;
              message = "shared-reference-tree: every participant's programs.ghq-shared.root must be ${cfg.root}.";
            }
            {
              assertion = rootRules == [ "d ${cfg.root} 0750 ${cfg.writer} ${cfg.writer} -" ];
              message = "shared-reference-tree: ${cfg.root} must be provisioned exactly once, mode 0750, owned by ${cfg.writer}.";
            }
          ];

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
