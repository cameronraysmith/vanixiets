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
