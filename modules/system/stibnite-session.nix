# The stibnite session: interactive access to stibnite under a dedicated
# keypair, exported as the two module keys this file is named for.
#
# Build access to stibnite is the nix-builders clan service
# (modules/clan/services/nix-builders). This is the other identity: an
# unrestricted login as admin-group crs58, who is already a Nix trusted user,
# so it grants build authority plus shell. It is authorized separately from the
# build key for independent revocation and rotation; only the build key is
# confined to the Nix protocol by `restrict` and a forced command.
#
# services.stibnite-session — the caller side: the keypair and its ssh alias.
# services.stibnite-session-host — the stibnite side: the authorization.
{ config, lib, ... }:
let
  stibniteZt = config.flake.lib.hosts.stibnite.zerotier.address;

  # clan's public var values carry the trailing newline of the file they were
  # read from, and an authorized_keys entry is one line.
  trimKey = key: lib.removeSuffix "\n" key;

  # Generated rather than operator-populated: no plaintext private half leaves
  # the caller. Clan commits the encrypted private half and public value, and
  # only that machine and authorized users can decrypt the private half. The
  # operator step is `clan vars generate <machine>` plus committing both
  # outputs; stibnite reads the public value at evaluation time.
  mkSessionKeyGenerator = pkgs: {
    clan.core.vars.generators.stibnite-agent-session = {
      files.key = { };
      files."key.pub".secret = false;
      runtimeInputs = [ pkgs.openssh ];
      script = ''
        ssh-keygen -t ed25519 -N "" -C "stibnite-agent-session" -f "$out"/key
      '';
    };
  };
in
{
  flake.modules.nixos.stibnite-session =
    { config, pkgs, ... }:
    let
      cfg = config.services.stibnite-session;
      sshKeyPath = config.clan.core.vars.generators.stibnite-agent-session.files.key.path;
    in
    {
      options.services.stibnite-session = {
        sshUser = lib.mkOption {
          type = lib.types.str;
          default = "crs58";
          description = "Account on stibnite this key logs in as.";
        };

        hostAlias = lib.mkOption {
          type = lib.types.str;
          default = "stibnite-session";
          description = "ssh Host alias for the session identity, distinct from the builder alias.";
        };
      };

      config = (mkSessionKeyGenerator pkgs) // {
        programs.ssh.extraConfig = ''
          Host ${cfg.hostAlias}
            HostName ${stibniteZt}
            User ${cfg.sshUser}
            IdentityFile ${sshKeyPath}
            IdentitiesOnly yes
            HostKeyAlias stibnite.zt
        '';
      };
    };

  flake.modules.darwin.stibnite-session-host =
    { config, lib, ... }:
    let
      cfg = config.services.stibnite-session-host;
    in
    {
      options.services.stibnite-session-host = {
        user = lib.mkOption {
          type = lib.types.str;
          default = "crs58";
          description = "Account the session keys log in as.";
        };

        keys = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Public keys authorized for an ordinary interactive login, with no forced command.";
        };
      };

      config = {
        users.users.${cfg.user}.openssh.authorizedKeys.keys = map trimKey cfg.keys;
      };
    };
}
