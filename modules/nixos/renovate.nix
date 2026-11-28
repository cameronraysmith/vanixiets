# Self-hosted Renovate for cameronraysmith/vanixiets on magnetite
# (openspec change stand-up-renovate-on-magnetite).
#
# Credential generator catalog:
#   - renovate-github-app-secret-key/key.pem: manual `clan vars set` (GitHub App PEM)
#
# The generator is declared unconditionally so that `clan vars set` can
# resolve it in magnetite's evaluated configuration; the unit and timer
# settings below sit behind services.renovate.enable.
#
# The key stays at the default root ownership. Only the privileged (`+`)
# ExecStartPre reads it, to mint a one-hour installation token per run into
# the unit's RuntimeDirectory; the main script moves the token into
# RENOVATE_TOKEN and deletes the file before Renovate starts. The module's
# own `credentials` option is not used: LoadCredential is read at unit start,
# before any ExecStartPre, so it could carry only the key itself, and every
# post-upgrade task child, which runs repository code under Renovate's uid,
# would then reach it. No restartUnits: each timer run reads the key afresh.
#
# Token lifetime: an installation token expires an hour after it is minted
# and Renovate never refreshes it, so RuntimeMaxSec stops a run at 55 minutes
# and every run mints a new token.
#
# Cadence (openspec automate-package-version-bumps design D7): the timer
# fires hourly at :17 plus up to 10 minutes of RandomizedDelaySec, and a run
# stops at 55 minutes, so a run never outlives its token; systemd does not
# start the unit while a run is still active. prCommitsPerRunLimit 4 caps the
# commits a run pushes, which with hourly runs matches the pin rule's
# prHourlyLimit of 4 in .github/renovate.json.
#
# Allowlist coupling: allowedCommands below is the only set of commands
# Renovate may run as post-upgrade tasks. A refused command still produces a
# pushed, incomplete commit, so the flake check renovate-allowed-commands
# requires every postUpgradeTasks command in .github/renovate.json to match
# one of these patterns.
#
# Tool coupling: tasks see only PATH and HOME, so every tool they need comes
# through runtimePackages. Their bun is the repository's toolchain bun (the
# one the default dev shell carries), asserted equal to package.json's
# packageManager, since a different bun can rewrite bun.lock differently.
#
# Token on argv: Renovate before 44.258.1 hands the token to `nix` as a
# command-line argument, readable by every local user through
# /proc/<pid>/cmdline, so an assertion refuses any older package. The service
# runs pkgs/by-name/renovate, which follows upstream releases through its pin
# and is withheld from the fleet overlay so no other consumer of
# pkgs.renovate moves with it.
#
# Hazard if the key is ever removed: `clan machines update` runs every
# missing generator for every machine before deploying anything, and this
# script exits non-zero, so deploys fail until the key is set again.
{ config, withSystem, ... }:
let
  inherit (config.flake.lib) renovateSettings;
in
{
  customPackageExcludes = [ "renovate" ];

  flake.modules.nixos.renovate =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.renovate;
      gen = config.vanixiets.secrets;
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
      repoBun = withSystem pkgs.stdenv.hostPlatform.system ({ pkgs, ... }: pkgs.bun);
      serviceRenovate = withSystem pkgs.stdenv.hostPlatform.system (
        { config, ... }: config.packages.renovate
      );
      packageManagerBun = lib.removePrefix "bun@" (lib.importJSON ../../package.json).packageManager;
    in
    {
      vanixiets.secrets.renovate-github-app-secret-key = {
        files."key.pem" = { };
        script = ''
          echo "renovate GitHub App private key: populate via clan vars set" >&2
          exit 1
        '';
      };

      services.renovate = {
        enable = true;
        package = serviceRenovate;
        schedule = "*-*-* *:17:00";
        runtimePackages = [
          config.nix.package
          repoBun
          pkgs.just
          pkgs.jq
          pkgs.bash
        ];
        settings = {
          platform = "github";
          repositories = [ "cameronraysmith/vanixiets" ];
          autodiscover = false;
          onboarding = false;
          requireConfig = "required";
          binarySource = "global";
          repositoryCache = "enabled";
          prCommitsPerRunLimit = 4;
          inherit (renovateSettings) allowedCommands;
        };
      };

      assertions = lib.mkIf cfg.enable [
        {
          assertion = repoBun.version == packageManagerBun;
          message = "renovate: task bun ${repoBun.version} differs from package.json packageManager bun@${packageManagerBun}; a different bun can rewrite bun.lock";
        }
        {
          assertion = lib.versionAtLeast cfg.package.version "44.258.1";
          message = "renovate: ${cfg.package.version} passes the GitHub token to nix on the command line; the service needs 44.258.1 or later";
        }
      ];

      systemd.services.renovate = lib.mkIf cfg.enable {
        script = lib.mkBefore ''
          RENOVATE_TOKEN="$(< /run/renovate/token)"
          export RENOVATE_TOKEN
          rm -f /run/renovate/token
        '';
        serviceConfig = {
          ExecStartPre = [ "+${lib.getExe mintToken}" ];
          RuntimeDirectory = "renovate";
          RuntimeDirectoryMode = "0700";
          RuntimeMaxSec = "55min";
          Nice = 10;
          CPUWeight = 20;
          IOWeight = 20;
          MemoryHigh = "4G";
          MemoryMax = "8G";
        };
      };

      systemd.timers.renovate = lib.mkIf cfg.enable {
        timerConfig.RandomizedDelaySec = "10min";
      };
    };
}
