# Bridge NixOS-level sops decryption to home-manager sops.age.keyFile
#
# On NixOS, the clan machine age key at /var/lib/sops-nix/key.txt decrypts
# a per-user age private key (the "bridge secret") at NixOS activation time.
# The decrypted key is then used by home-manager's sops-nix module to decrypt
# user-level secrets (API keys, signing keys, etc.) during HM activation.
#
# This eliminates the manual step of provisioning ~/.config/sops/age/keys.txt
# on each NixOS host via Bitwarden extraction + SCP.
#
# Darwin homes are unaffected: they read ~/.config/sops/age/keys.txt (the
# mkDefault in base-sops), which holds the person's key derived from their
# Bitwarden SSH key; see "Workstation age key" in the secrets guide.
#
# Each bridged user also gets an assertion that this host's machine key
# (sops/machines/<host>/key.json) is a recipient of the bridge file, so a host
# added without re-encrypting the bridge fails evaluation, not activation.
#
# Activation mode, measured 2026-09-18 by `nix eval` over all six NixOS hosts
# (cinnabar, electrum, galena, magnetite, pyrite, scheelite): sops.useSystemdActivation,
# services.userborn.enable and systemd.sysusers.enable are all false, so the whole
# fleet decrypts through the setupSecrets activation script. That script is ordered
# after the "users" and "groups" activation snippets, so the bridge secret exists with
# its final ownership before any home-manager activation runs and the ordering relative
# to home-manager is free. srvos would otherwise enable userborn, but its definition in
# srvos nixos/common/default.nix is guarded by lib.mkIf over a condition that is false
# whenever any user sets subUidRanges or autoSubUidGidRange, and nixpkgs
# config/users-groups.nix sets autoSubUidGidRange = mkDefault true for every
# isNormalUser; each host declares at least one. Removing the normal users, or setting
# sops.useSystemdActivation, flips the fleet into systemd mode.
#
# In systemd mode the ordering is no longer free: sops-nix gives
# sops-install-secrets.service requiredBy/before sysinit-reactivation.target, while
# home-manager's NixOS module orders home-manager-<user>.service only after
# nix-daemon.socket and before systemd-user-sessions.service and declares no dependency
# on any secret store. A switch-time race between key delivery and home-manager
# activation is therefore possible in that mode. It does not exist in ours today.
#
# The home view: every home-manager user of a host, bridged or not, gets the
# home option
# flake.modules.homeManager.secrets (modules/system/secrets.nix) set to the
# host's `vanixiets.secrets` entries with a file that user owns, projected to
# each file's delivered `path` and sops `placeholder`, never its contents. The
# view is set from a shared home module keyed on `home.username`, because a
# host-level definition of `home-manager.users` derived from that option's own
# names would recurse. flake.modules.darwin.hm-sops-bridge carries only the
# view; nixos.base and darwin.base import the two modules.
#
# The age-key bridge has no OpenSpec change and no ADR: its introducing commit
# 5be53d720 carries a subject line and no body, so this header is its entire
# design record.
flakeArgs@{ ... }:
let
  inherit (flakeArgs.config.flake.lib) exportAs;

  homeView =
    { config, lib, ... }:
    let
      hostSecrets = config.vanixiets.secrets;
      view =
        user:
        lib.mapAttrs (_: s: {
          files = lib.mapAttrs (_: f: { inherit (f) path placeholder; }) (
            lib.filterAttrs (_: f: f.owner == user) s.files
          );
        }) (lib.filterAttrs (_: s: lib.any (f: f.owner == user) (lib.attrValues s.files)) hostSecrets);
    in
    {
      home-manager.sharedModules = [
        flakeArgs.config.flake.modules.homeManager.secrets
        ({ config, ... }: { vanixiets.secrets = view config.home.username; })
      ];
    };

  bridge =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.hm-sops-bridge;

      flakeUsers = flakeArgs.config.flake.users;

      userOpts = lib.types.submodule (
        { name, ... }:
        {
          options.sopsIdentity = lib.mkOption {
            type = lib.types.str;
            default =
              flakeUsers.${name}.meta.sopsAgeKeyId
                or (throw "hm-sops-bridge.users.${name}.sopsIdentity has no default: flake.users.${name}.meta.sopsAgeKeyId is unset");
            defaultText = lib.literalExpression "config.flake.users.\${name}.meta.sopsAgeKeyId";
            description = ''
              Sops identity name used in the bridge secret filename (e.g. 'crs58'
              for secrets/bridge/crs58-age-key.enc).

              Defaults to `flake.users.<name>.meta.sopsAgeKeyId`, which after
              alias-fold propagates the canonical user's identity to alias
              entries (e.g. `cameron` inherits `crs58`). Override only when the
              host-local identity differs from the typed registry.
            '';
          };
        }
      );
    in
    {
      imports = [ homeView ];

      options.hm-sops-bridge.users = lib.mkOption {
        type = lib.types.attrsOf userOpts;
        default = { };
        description = "Users whose age keys should be bridged from NixOS-level sops to home-manager";
      };

      config = lib.mkIf (cfg.users != { }) {
        assertions = lib.concatLists (
          lib.mapAttrsToList (
            username: userCfg:
            let
              host = config.clan.core.settings.machine.name;
              bridgeFile = ../../secrets/bridge/${userCfg.sopsIdentity}-age-key.enc;
              machineKeyFile = ../../sops/machines/${host}/key.json;
              bridgeExists = builtins.pathExists bridgeFile;
              # The binary sops store is JSON on disk; recipients are public metadata.
              recipients = map (r: r.recipient) (builtins.fromJSON (builtins.readFile bridgeFile)).sops.age;
              machineKey = (builtins.head (builtins.fromJSON (builtins.readFile machineKeyFile))).publickey;
            in
            [
              {
                assertion = bridgeExists;
                message = ''
                  hm-sops-bridge.users.${username} uses sops identity "${userCfg.sopsIdentity}",
                  but secrets/bridge/${userCfg.sopsIdentity}-age-key.enc does not exist.

                  Commit the bridge secret for that identity, or point
                  hm-sops-bridge.users.${username}.sopsIdentity (default:
                  flake.users.${username}.meta.sopsAgeKeyId) at an identity that has one.
                '';
              }
              {
                assertion = !bridgeExists || (builtins.pathExists machineKeyFile && lib.elem machineKey recipients);
                message = ''
                  ${host} bridges sops identity "${userCfg.sopsIdentity}" for ${username}, but
                  secrets/bridge/${userCfg.sopsIdentity}-age-key.enc is not encrypted to ${host}'s
                  machine key (sops/machines/${host}/key.json), so the host could not decrypt it.

                  Add the ${host} anchor to the secrets/bridge/ rule in .sops.yaml and run
                  `just update-all-keys`.
                '';
              }
            ]
          ) cfg.users
        );

        sops.secrets = lib.mapAttrs' (
          username: userCfg:
          lib.nameValuePair "${userCfg.sopsIdentity}-age-key" {
            sopsFile = ../../secrets/bridge/${userCfg.sopsIdentity}-age-key.enc;
            format = "binary";
            owner = username;
            mode = "0400";
          }
        ) cfg.users;

        home-manager.users = lib.mapAttrs (username: userCfg: {
          sops.age.keyFile = config.sops.secrets."${userCfg.sopsIdentity}-age-key".path;
        }) cfg.users;
      };
    };

  exportBridge =
    module:
    exportAs {
      key = "hm-sops-bridge";
      names = [ "hm-sops-bridge" ];
      inherit module;
    };
  nixos = exportBridge bridge;
  darwin = exportBridge homeView;
in
{
  flake.modules.nixos = nixos;
  flake.modules.darwin = darwin // {
    base.imports = [ darwin.hm-sops-bridge ];
  };
}
