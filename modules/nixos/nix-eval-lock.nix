# Host evaluation lock: one nix-eval-jobs at a time per host, and the
# evaluator first in line for the OOM killer.
#
# magnetite was OOM-killed twice (2026-09-27, 2026-10-01) by nixbot's 8 x 4096
# evaluation overlapping a remote `just check-fast` evaluation, and the kernel
# chose nix-daemon connection workers (oom_score_adj 250) as victims rather
# than either evaluator. With this capability every nix-eval-jobs on the host
# (nixbot's, and the one `nix-fast-build --remote` finds on an ssh
# user's PATH) queues on one lock, and the running one sits at
# oom_score_adj 900, where a kill costs a worker that nix-eval-jobs >= 2.35.3
# requeues and retries alone. Mechanism and its constraints:
# modules/lib/nix-eval-lock.sh.
#
# The lock is /etc/nix/eval.lock (with its companion /etc/nix/eval.lock.owner,
# see the script), not a /run path, because nixbot evaluates inside a
# bubblewrap sandbox whose filesystem is a tmpfs plus an explicit bind list
# (nixbot/nixbot/nix_eval.py SANDBOX_ETC_PATHS); /etc/nix is on that list,
# /run is not. The files are created by tmpfiles (`f` creates only when
# absent), so they keep their inodes across activations: setup-etc.pl removes
# only dangling /etc/static symlinks and files recorded in /etc/.clean, and
# these are neither. Mode 0444 root: every user can open them read-only, which
# is all flock(2) needs, and no user can truncate or replace them.
#
# Consumers install the wrapper through services.nixEvalLock.wrap, which keeps
# each service's own evaluator build underneath (a service may ship its own).
# The host's own nix-eval-jobs (services.nixEvalLock.package, on the system
# PATH and in every home on the host) wraps iets at the bound the host's
# memory gives it (flake.lib.nixEvalJobsBound), with the wrapped stock as
# nix-eval-jobs-stock beside it, or wraps stock alone on a host without a
# bound (modules/lib/nix-eval-jobs-host.nix).
#
# The failure the assertions guard is silent: a service or user resolving the
# bare `nix-eval-jobs` to an unwrapped binary evaluates outside the lock, which
# is exactly the overlap that OOM-killed magnetite, and nothing about the run
# looks different. nixbot runs the bare name from its unit
# PATH, and `nix-fast-build --remote` runs it from the ssh user's PATH, where a
# Home Manager or per-user package precedes the system profile.
{ config, ... }:
let
  flakeLib = config.flake.lib;
in
{
  # Every NixOS host imports the capability; it is enabled where the host
  # table gives the host iets (flake.lib.nixEvalJobsBound) or where the host
  # enables it itself.
  flake.modules.nixos.base.imports = [ config.flake.modules.nixos.nix-eval-lock ];

  flake.modules.nixos.nix-eval-lock =
    {
      config,
      options,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.nixEvalLock;
      evaluators = flakeLib.nixEvalJobsPackages pkgs {
        inherit (cfg) bound wrap;
      };

      unwrappedProfiles = flakeLib.nixEvalLockUnwrapped (
        lib.mapAttrs' (n: u: lib.nameValuePair "users.users.${n}.packages" u.packages) config.users.users
        // lib.optionalAttrs (options ? home-manager) (
          lib.mapAttrs' (
            n: u: lib.nameValuePair "home-manager.users.${n}.home.packages" u.home.packages
          ) config.home-manager.users
        )
        // {
          "environment.systemPackages" = config.environment.systemPackages;
        }
      );
      unwrappedServices = flakeLib.nixEvalLockUnwrapped (
        lib.mapAttrs (_: s: s.path) config.systemd.services
      );
    in
    {
      options.services.nixEvalLock = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = cfg.bound != null;
          defaultText = lib.literalExpression "config.services.nixEvalLock.bound != null";
          description = "Whether to serialise every nix-eval-jobs on the host behind the host evaluation lock; required where the host evaluates with iets.";
        };

        bound = lib.mkOption {
          type = lib.types.nullOr lib.types.attrs;
          default = flakeLib.nixEvalJobsBound config.networking.hostName;
          defaultText = lib.literalExpression "flake.lib.nixEvalJobsBound config.networking.hostName";
          readOnly = true;
          description = "iets' bound (workers, maxMemorySize) from the host's memory in flake.lib.hosts, or null where the host keeps stock nix-eval-jobs.";
        };

        lockFile = lib.mkOption {
          type = lib.types.str;
          default = "/etc/nix/eval.lock";
          readOnly = true;
          description = "Lock file every wrapped nix-eval-jobs on the host takes an exclusive flock on.";
        };

        wrap = lib.mkOption {
          type = lib.types.functionTo lib.types.package;
          default = flakeLib.wrapNixEvalJobsWithLock pkgs cfg.lockFile;
          defaultText = lib.literalExpression "flake.lib.wrapNixEvalJobsWithLock pkgs config.services.nixEvalLock.lockFile";
          readOnly = true;
          description = "Wraps a nix-eval-jobs package with the host lock, keeping its version and nix passthru.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = evaluators.package;
          defaultText = lib.literalExpression "config.services.nixEvalLock.wrap of iets at config.services.nixEvalLock.bound, or of pkgs.nix-eval-jobs where it is null";
          readOnly = true;
          description = "The wrapped nix-eval-jobs installed on the system PATH: iets where the host table gives the host a bound, stock otherwise.";
        };

        stockPackage = lib.mkOption {
          type = lib.types.nullOr lib.types.package;
          default = evaluators.stockPackage;
          defaultText = lib.literalExpression "nix-eval-jobs-stock, the wrapped pkgs.nix-eval-jobs, where package is iets; null otherwise";
          readOnly = true;
          description = "The wrapped stock evaluator installed as nix-eval-jobs-stock where package is iets, for what iets refuses (import-from-derivation, --override-input, --override-flake, --repair, --help).";
        };
      };

      config = lib.mkMerge [
        {
          assertions = [
            {
              # iets fails the whole evaluation when one of its workers is
              # OOM-killed, so it never runs beside another evaluation.
              assertion = cfg.bound == null || cfg.enable;
              message = "nix-eval-lock: ${config.networking.hostName} evaluates with iets (flake.lib.hosts memoryGiB) and must keep the host evaluation lock enabled";
            }
          ];
        }
        (lib.mkIf cfg.enable {

          systemd.tmpfiles.rules = [
            "f ${cfg.lockFile} 0444 root root -"
            "f ${cfg.lockFile}.owner 0444 root root -"
          ];

          # hiPrio so an interactive or ssh user's `nix-eval-jobs`, which is what
          # `nix-fast-build --remote` runs, is the wrapper even if some other
          # system package also ships the binary.
          environment.systemPackages = [
            (lib.hiPrio cfg.package)
          ]
          ++ lib.optional (cfg.stockPackage != null) cfg.stockPackage;

          assertions = [
            {
              assertion = unwrappedProfiles == [ ];
              message = "nix-eval-lock: unwrapped nix-eval-jobs (bypassing ${cfg.lockFile}) in: ${lib.concatStringsSep ", " unwrappedProfiles}";
            }
            {
              assertion = unwrappedServices == [ ];
              message = "nix-eval-lock: unwrapped nix-eval-jobs (bypassing ${cfg.lockFile}) on the PATH of systemd services: ${lib.concatStringsSep ", " unwrappedServices}";
            }
            {
              # OpenSSH already holds its listener at -1000 and restores the
              # unit's value in every session it forks, so setting one would make
              # every ssh session, and the evaluator it runs, OOM-immune
              # (modules/nixos/memory-pressure-guards.nix).
              assertion = !((config.systemd.services.sshd.serviceConfig or { }) ? OOMScoreAdjust);
              message = "nix-eval-lock: sshd must carry no OOMScoreAdjust; every ssh session would inherit it";
            }
          ];
        })
      ];
    };
}
