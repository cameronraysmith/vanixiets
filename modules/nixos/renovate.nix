# Self-hosted Renovate for cameronraysmith/vanixiets on magnetite
# (openspec change stand-up-renovate-on-magnetite).
#
# Credential generator catalog:
#   - renovate-github-app-secret-key/key.pem: manual `clan vars set` (GitHub App PEM)
#
# The generator is declared unconditionally so that `clan vars set` can
# resolve it in magnetite's evaluated configuration. Everything else sits
# behind services.renovate.enable, which is set only together with the
# Phase 1 full-dry-run settings (dryRun, the temporary branchPrefix, the
# global packageRules and debug logging), so the first deployed updater
# writes nothing to the forge.
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
# Allowlist coupling: allowedCommands below is the only set of commands
# Renovate may run as post-upgrade tasks. A refused command still produces a
# pushed, incomplete commit, so the flake check renovate-allowed-commands
# requires every postUpgradeTasks command in .github/renovate.json and in any
# global packageRules here to match one of these patterns.
#
# Tool coupling: tasks see only PATH and HOME, so every tool they need comes
# through runtimePackages. Their bun is the repository's toolchain bun (the
# one the default dev shell carries), asserted equal to package.json's
# packageManager, since a different bun can rewrite bun.lock differently.
#
# Hazard if the key is ever removed: `clan machines update` runs every
# missing generator for every machine before deploying anything, and this
# script exits non-zero, so deploys fail until the key is set again.
{ config, withSystem, ... }:
let
  inherit (config.flake.lib) renovateSettings;
in
{
  flake.modules.nixos.renovate =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.renovate;
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
      repoBun = withSystem pkgs.stdenv.hostPlatform.system ({ pkgs, ... }: pkgs.bun);
      packageManagerBun = lib.removePrefix "bun@" (lib.importJSON ../../package.json).packageManager;
    in
    {
      clan.core.vars.generators.renovate-github-app-secret-key = {
        files."key.pem" = { };
        script = ''
          echo "renovate GitHub App private key: populate via clan vars set" >&2
          exit 1
        '';
      };

      services.renovate = lib.mkMerge [
        {
          enable = true;
        }
        (lib.mkIf cfg.enable {
          schedule = "*-*-* 00/2:17:00";
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

            # Phase 1 only; removed by tasks.md 7.4. A full dry run performs
            # artifact updates and post-upgrade tasks but writes nothing to the
            # forge.
            dryRun = "full";
            # The temporary prefix alone does not keep the hosted app's
            # renovate/* branches out of the run: branchPrefixOld defaults to
            # `renovate/` (Renovate 44.236.2 lib/config/options/index.ts:2248-2254),
            # and when a branch under branchPrefix does not exist Renovate
            # adopts the same-named branch under branchPrefixOld
            # (lib/workers/repository/update/branch/index.ts:88-97, and for PRs
            # update/branch/check-existing.ts:30), finds it written by
            # renovate[bot], treats it as edited and skips it. The first Phase 1
            # run skipped every candidate branch that way. Setting both to the
            # same value disables the old-prefix lookup, which both sites guard
            # with `branchPrefix !== branchPrefixOld`.
            branchPrefix = "renovate-selfhost/";
            branchPrefixOld = "renovate-selfhost/";
            packageRules = renovateSettings.phase1PackageRules;
          };
        })
      ];

      assertions = lib.mkIf cfg.enable [
        {
          assertion = repoBun.version == packageManagerBun;
          message = "renovate: task bun ${repoBun.version} differs from package.json packageManager bun@${packageManagerBun}; a different bun can rewrite bun.lock";
        }
      ];

      systemd.services.renovate = lib.mkIf cfg.enable {
        # Phase 1 only; removed by tasks.md 7.4, together with LogsDirectory and
        # the rotation step below. Task 5.4 needs every GitHub request for the
        # permission trim. Renovate reports per-URL, per-method counts only at
        # trace ("HTTP URL statistics", lib/util/stats.ts HttpStats.report; at
        # debug only per-host totals and the HTTP cache's GET paths), and trace
        # in the journal produced about 12.5 million lines per run, which
        # journald's rate limit discarded. So the journal stays at debug and a
        # trace log file takes the rest (LOG_FILE, LOG_FILE_LEVEL,
        # lib/logger/bunyan.ts:44-59). The file stream goes through the same
        # sanitizer as stdout (bunyan.ts serializedSanitizedLogger maps every
        # stream through withSanitizer, with-sanitizer.ts applying
        # logger/utils.ts sanitizeValue): `authorization` and `token` fields
        # are masked (lib/util/sanitize.ts:7-23), and the platform token's value
        # is replaced anywhere in a message, because platform init registers it
        # as a host rule (lib/modules/platform/index.ts:74-94), host rules
        # register their token for sanitizing (lib/util/host-rules.ts:268-281),
        # the per-repository reset re-adds them
        # (lib/workers/global/index.ts:225-232), and an App token is registered
        # with and without its `x-access-token:` prefix
        # (lib/util/sanitize.ts:47-64). Renovate cannot rotate the file
        # (with-sanitizer.ts rejects rotating files), so each run first moves
        # the previous run's file aside: at most two runs stay on disk, each
        # estimated at 1-2 GB from the 2026-11-17 trace run's line count.
        environment = {
          LOG_LEVEL = "debug";
          LOG_FILE = "/var/log/renovate/trace.ndjson";
          LOG_FILE_LEVEL = "trace";
        };
        script = lib.mkBefore ''
          RENOVATE_TOKEN="$(< /run/renovate/token)"
          export RENOVATE_TOKEN
          rm -f /run/renovate/token
        '';
        serviceConfig = {
          ExecStartPre = [
            "+${lib.getExe mintToken}"
            # `-`: the first run has no previous file to move.
            "-${pkgs.coreutils}/bin/mv -f /var/log/renovate/trace.ndjson /var/log/renovate/trace.previous.ndjson"
          ];
          RuntimeDirectory = "renovate";
          RuntimeDirectoryMode = "0700";
          LogsDirectory = "renovate";
          LogsDirectoryMode = "0700";
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
