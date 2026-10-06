# Host evaluation lock: one nix-eval-jobs at a time per host, and the
# evaluator first in line for the OOM killer.
#
# magnetite was OOM-killed twice (2026-09-27, 2026-10-01) by nixbot's 8 x 4096
# evaluation overlapping a remote `just check-fast` evaluation, and the kernel
# chose nix-daemon connection workers (oom_score_adj 250) as victims rather
# than either evaluator. With this capability every nix-eval-jobs on the host
# (nixbot's, buildbot's, and the one `nix-fast-build --remote` finds on an ssh
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
# each service's own evaluator build underneath (nixbot and buildbot-nix ship
# different ones).
#
# The failure the assertions guard is silent: a service or user resolving the
# bare `nix-eval-jobs` to an unwrapped binary evaluates outside the lock, which
# is exactly the overlap that OOM-killed magnetite, and nothing about the run
# looks different. nixbot and buildbot-nix run the bare name from their unit
# PATH, and `nix-fast-build --remote` runs it from the ssh user's PATH, where a
# Home Manager or per-user package precedes the system profile.
{ config, ... }:
let
  flakeLib = config.flake.lib;
in
{
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

      # A wrapper carries the evaluator it wraps as `unwrapped`, and must
      # forward that evaluator's nix CLI passthru (nixbot puts it on its
      # service PATH).
      evaluatorsOf = builtins.filter (
        p: builtins.isAttrs p && (p.pname or p.name or "") == "nix-eval-jobs"
      );
      isWrapped =
        p: p ? unwrapped && (!(p.unwrapped ? nix) || (p ? nix && p.nix.drvPath == p.unwrapped.nix.drvPath));
      unwrappedIn =
        lists: lib.attrNames (lib.filterAttrs (_: ps: !lib.all isWrapped (evaluatorsOf ps)) lists);

      unwrappedProfiles = unwrappedIn (
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
      unwrappedServices = unwrappedIn (lib.mapAttrs (_: s: s.path) config.systemd.services);
    in
    {
      options.services.nixEvalLock = {
        enable = lib.mkEnableOption "the host evaluation lock around nix-eval-jobs";

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
          default = cfg.wrap pkgs.nix-eval-jobs;
          defaultText = lib.literalExpression "config.services.nixEvalLock.wrap pkgs.nix-eval-jobs";
          readOnly = true;
          description = "The wrapped nix-eval-jobs installed on the system PATH.";
        };
      };

      config = lib.mkIf cfg.enable {
        systemd.tmpfiles.rules = [
          "f ${cfg.lockFile} 0444 root root -"
          "f ${cfg.lockFile}.owner 0444 root root -"
        ];

        # hiPrio so an interactive or ssh user's `nix-eval-jobs`, which is what
        # `nix-fast-build --remote` runs, is the wrapper even if some other
        # system package also ships the binary.
        environment.systemPackages = [ (lib.hiPrio cfg.package) ];

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
      };
    };
}
