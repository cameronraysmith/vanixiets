# Self-hosted Renovate for cameronraysmith/vanixiets on magnetite
# (openspec change stand-up-renovate-on-magnetite).
#
# Credential generator catalog:
#   - renovate-github-app-secret-key/key.pem: manual `clan vars set` (GitHub App PEM)
#
# The generator is declared unconditionally so that `clan vars set` can
# resolve it in magnetite's evaluated configuration. Everything else sits
# behind services.renovate.enable, which this aspect does not set until the
# Phase 1 dry-run configuration, so no deploy runs a live updater before the
# key and the dry-run settings both exist.
#
# The key stays at the default root ownership. Only the privileged (`+`)
# ExecStartPre reads it, to mint a one-hour installation token per run into
# the unit's RuntimeDirectory; the main script moves the token into
# RENOVATE_TOKEN and deletes the file before Renovate starts. The sandboxed
# process, where post-upgrade tasks run repository code under Renovate's uid,
# never sees the key. No restartUnits: each timer run reads the key afresh.
#
# Hazard until the key is set: `clan machines update` runs every missing
# generator for every machine before deploying anything, and this script
# exits non-zero, so deploys from a tree carrying this declaration fail until
# `clan vars set magnetite renovate-github-app-secret-key/key.pem` has run.
{
  flake.modules.nixos.renovate =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      gen = config.clan.core.vars.generators;
      # GitHub App vanixiets-renovate and its installation on
      # cameronraysmith/vanixiets. Identifiers, not secrets.
      appId = 5795103;
      installationId = 182811092;
      mintToken = pkgs.writeShellApplication {
        name = "renovate-mint-token";
        runtimeInputs = [
          pkgs.gh-token
          pkgs.coreutils
        ];
        text = ''
          umask 077
          gh-token generate --token-only \
            --key ${gen.renovate-github-app-secret-key.files."key.pem".path} \
            --app-id ${toString appId} --installation-id ${toString installationId} \
            > /run/renovate/token
          chown --reference=/run/renovate /run/renovate/token
        '';
      };
    in
    {
      clan.core.vars.generators.renovate-github-app-secret-key = {
        files."key.pem" = { };
        script = ''
          echo "renovate GitHub App private key: populate via clan vars set" >&2
          exit 1
        '';
      };

      systemd.services.renovate = lib.mkIf config.services.renovate.enable {
        script = lib.mkBefore ''
          RENOVATE_TOKEN="$(< /run/renovate/token)"
          export RENOVATE_TOKEN
          rm -f /run/renovate/token
        '';
        serviceConfig = {
          ExecStartPre = [ "+${lib.getExe mintToken}" ];
          RuntimeDirectory = "renovate";
          RuntimeDirectoryMode = "0700";
        };
      };
    };
}
