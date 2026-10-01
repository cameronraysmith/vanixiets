# Structural check that every evaluator on the hosts with the evaluation lock
# is the locking wrapper (modules/nixos/nix-eval-lock.nix).
#
# The failure it guards is silent: a service or user resolving the bare
# `nix-eval-jobs` to an unwrapped binary evaluates outside the lock, which is
# exactly the overlap that OOM-killed magnetite, and nothing about the run
# looks different. nixbot and buildbot-nix run the bare name from their unit
# PATH, and `nix-fast-build --remote` runs it from the ssh user's PATH, where
# a Home Manager or per-user package precedes the system profile. The check
# reads each of those off the evaluated configuration, together with the
# evaluator each service wrapper sits over (it must be the one the service
# would otherwise have used, so the wrapper changes nothing but the locking).
#
# sshd is pinned to carry no OOMScoreAdjust: OpenSSH already holds its
# listener at -1000 and restores the unit's value in every session it forks,
# so setting one would make every ssh session OOM-immune
# (modules/nixos/memory-pressure-guards.nix).
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      mkCheck = self.lib.mkStructuralCheck pkgs;

      # Path entries that provide `nix-eval-jobs`, as (wrapped, priority).
      # Wrappers carry the evaluator they wrap as `unwrapped`.
      evaluators =
        packages:
        map (p: {
          wrapped = p ? unwrapped;
          priority = p.meta.priority or lib.meta.defaultPriority;
        }) (builtins.filter (p: (p.pname or p.name or "") == "nix-eval-jobs") packages);

      host =
        name:
        let
          cfg = self.nixosConfigurations.${name}.config;
          # Users whose own profile carries an unwrapped nix-eval-jobs, which
          # would shadow the system wrapper on their PATH.
          profiles =
            lib.mapAttrs (_: u: evaluators u.packages) cfg.users.users
            // lib.mapAttrs (_: u: evaluators u.home.packages) cfg.home-manager.users;
        in
        {
          systemPath = evaluators cfg.environment.systemPackages;
          usersShadowingTheWrapper = lib.attrNames (
            lib.filterAttrs (_: entries: !lib.all (e: e.wrapped) entries) profiles
          );
          lockFiles = builtins.filter (lib.hasInfix "/etc/nix/eval.lock") cfg.systemd.tmpfiles.rules;
          sshdOomScoreAdjust = cfg.systemd.services.sshd.serviceConfig.OOMScoreAdjust or null;
        };

      magnetite = self.nixosConfigurations.magnetite;
      m = magnetite.config;
      sameDrv = a: b: a.drvPath == b.drvPath;

      expectedHost = {
        systemPath = [
          {
            wrapped = true;
            priority = -10;
          }
        ];
        usersShadowingTheWrapper = [ ];
        lockFiles = [
          "f /etc/nix/eval.lock 0444 root root -"
          "f /etc/nix/eval.lock.owner 0444 root root -"
        ];
        sshdOomScoreAdjust = null;
      };
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        nix-eval-lock-wiring = mkCheck {
          name = "nix-eval-lock-wiring";
          actual = {
            magnetite = host "magnetite";
            pyrite = host "pyrite";
            nixbotPath = evaluators m.systemd.services.nixbot.path;
            buildbotWorkerPath = evaluators m.systemd.services.buildbot-worker.path;
            nixbotWrapsItsOwnEvaluator = sameDrv m.services.nixbot.packages.nix-eval-jobs.unwrapped magnetite.options.services.nixbot.packages.nix-eval-jobs.default;
            # nixbot's patched nix CLI rides on the evaluator package; the
            # wrapper must forward it or the service PATH loses it.
            nixbotNixCliForwarded = sameDrv m.services.nixbot.packages.nix-eval-jobs.nix magnetite.options.services.nixbot.packages.nix-eval-jobs.default.nix;
            buildbotWrapsItsOwnEvaluator = sameDrv m.services.buildbot-nix.worker.nixEvalJobs.package.unwrapped magnetite.options.services.buildbot-nix.worker.nixEvalJobs.package.default;
          };
          expected = {
            magnetite = expectedHost;
            pyrite = expectedHost;
            nixbotPath = [
              {
                wrapped = true;
                priority = lib.meta.defaultPriority;
              }
            ];
            buildbotWorkerPath = [
              {
                wrapped = true;
                priority = lib.meta.defaultPriority;
              }
            ];
            nixbotWrapsItsOwnEvaluator = true;
            nixbotNixCliForwarded = true;
            buildbotWrapsItsOwnEvaluator = true;
          };
        };
      };
    };
}
