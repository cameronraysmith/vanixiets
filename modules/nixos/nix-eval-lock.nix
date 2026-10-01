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
{ config, ... }:
let
  flakeLib = config.flake.lib;
in
{
  flake.modules.nixos.nix-eval-lock =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.nixEvalLock;
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
      };
    };
}
