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
# Darwin hosts are unaffected: they continue using the Bitwarden SSH agent
# workflow with the XDG-path key file (set via mkDefault in base-sops).
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
# This module has no OpenSpec change and no ADR: its introducing commit 5be53d720 carries
# a subject line and no body, so this header is the entire design record.
flakeArgs@{ inputs, ... }:
{
  flake.modules.nixos.hm-sops-bridge =
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
      options.hm-sops-bridge.users = lib.mkOption {
        type = lib.types.attrsOf userOpts;
        default = { };
        description = "Users whose age keys should be bridged from NixOS-level sops to home-manager";
      };

      config = lib.mkIf (cfg.users != { }) {
        assertions = lib.mapAttrsToList (username: _userCfg: {
          assertion =
            (flakeUsers ? ${username}) && (flakeUsers.${username}.meta.sopsAgeKeyId or null) != null;
          message = ''
            hm-sops-bridge.users.${username} is enabled but
            flake.users.${username}.meta.sopsAgeKeyId is null or unset.

            Set sopsAgeKeyId in modules/home/users/${username}/meta.nix (for
            canonical users) or ensure the alias target has it set (alias-fold
            inherits meta from the target). Alternatively, override
            hm-sops-bridge.users.${username}.sopsIdentity at the host level.
          '';
        }) cfg.users;

        sops.secrets = lib.mapAttrs' (
          username: userCfg:
          lib.nameValuePair "${userCfg.sopsIdentity}-age-key" {
            sopsFile = inputs.self + "/secrets/bridge/${userCfg.sopsIdentity}-age-key.enc";
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
}
