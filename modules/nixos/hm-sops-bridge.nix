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
{
  config,
  inputs,
  ...
}:
{
  flake.modules.nixos.hm-sops-bridge =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.hm-sops-bridge;

      userOpts = lib.types.submodule {
        options.sopsIdentity = lib.mkOption {
          type = lib.types.str;
          description = "Sops identity name used in the bridge secret filename (e.g. 'crs58' for secrets/bridge/crs58-age-key.enc)";
        };
      };
    in
    {
      options.hm-sops-bridge.users = lib.mkOption {
        type = lib.types.attrsOf userOpts;
        default = { };
        description = "Users whose age keys should be bridged from NixOS-level sops to home-manager";
      };

      config = lib.mkIf (cfg.users != { }) {
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
