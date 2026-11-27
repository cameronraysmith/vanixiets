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
      # The handler's per-repository lock files; the writer creates them and never
      # removes them.
      lockDir = "/var/lib/ghq-writer";
      handlerConfig = pkgs.writeText "ghq-writer.json" (
        builtins.toJSON {
          inherit (cfg) root allowedProtocols;
          inherit lockDir;
          group = cfg.writer;
        }
      );
      lazygitPath = "${cfg.root}/.lazygit.yml";
      # tmpfiles reads C-style escapes in the argument; f+ rewrites the file at each run.
      lazygitRule = "f+ ${lazygitPath} 0640 ${cfg.writer} ${cfg.writer} - ${
        lib.replaceStrings [ "\n" ] [ "\\n" ] flakeConfig.flake.lib.sharedReferenceTreeLazygitConfig
      }";
    in
    {
      imports = [ flakeConfig.flake.modules.nixos.shared-reference-tree-options ];

      config = {
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
            lfsPolicy = flakeConfig.flake.lib.sharedReferenceTreeLfsPolicy;
            runsNoLfsFilter =
              user:
              lib.all (
                form:
                lib.any (
                  include:
                  include.condition == "gitdir:${form}/" && (include.contents.filter.lfs or null) == lfsPolicy
                ) (hm.${user}.programs.git.includes or [ ])
              ) cfg.rootForms;
            rootRules = lib.filter (
              rule:
              let
                fields = lib.splitString " " rule;
              in
              builtins.length fields > 1 && builtins.elemAt fields 1 == cfg.root
            ) config.systemd.tmpfiles.rules;
            lazygitRules = lib.filter (
              rule:
              let
                fields = lib.splitString " " rule;
              in
              builtins.length fields > 1 && builtins.elemAt fields 1 == lazygitPath
            ) config.systemd.tmpfiles.rules;
            transportOpen = lib.concatMap (
              user:
              map (gap: "${user}: ${gap}") (
                flakeConfig.flake.lib.sharedReferenceTreeTransportGaps cfg.rootForms hm.${user}
              )
            ) cfg.participants;
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
              assertion = lib.all conforms (lib.attrNames hm);
              message = "shared-reference-tree: each participant's safe.directory must be exactly ${cfg.root}/*, and no account's may be * or enclose ${cfg.root}.";
            }
            {
              assertion = lib.all runsNoLfsFilter cfg.participants;
              message = "shared-reference-tree: every participant's git must run no LFS filter in the shared tree: an include with condition gitdir:<form>/ setting filter.lfs to ${builtins.toJSON lfsPolicy}, for each of ${toString cfg.rootForms}.";
            }
            {
              assertion = transportOpen == [ ];
              message = "shared-reference-tree: every participant's git must refuse every transport in the shared tree, with an include with condition gitdir:<form>/ setting protocol.allow to never for each of ${toString cfg.rootForms}, no protocol.<name>.allow in its settings, and no include that can apply there setting protocol.<name>.allow or a protocol.allow other than never; not so: ${lib.concatStringsSep "; " transportOpen}.";
            }
            {
              assertion = lib.all (
                user: (hm.${user}.programs.git.settings.safe.bareRepository or null) == "explicit"
              ) cfg.participants;
              message = "shared-reference-tree: every participant's safe.bareRepository must be explicit.";
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
            {
              assertion = lazygitRules == [ lazygitRule ];
              message = "shared-reference-tree: ${lazygitPath} must be provisioned exactly once, mode 0640, owned by ${cfg.writer}, turning off lazygit's start-up fetch.";
            }
          ];

        services.shared-reference-tree.rootForms = [ cfg.root ];

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

        systemd.tmpfiles.rules = [
          "d ${cfg.root} 0750 ${cfg.writer} ${cfg.writer} -"
          lazygitRule
          "d ${lockDir} 0700 ${cfg.writer} ${cfg.writer} -"
        ];

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
            ReadWritePaths = [
              cfg.root
              lockDir
            ];
          };
        };
      };
    };
}
