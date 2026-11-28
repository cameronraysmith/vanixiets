# nix-build-locked: the host's build lock and memory-pressure ceiling
# (modules/lib/nix-build-lock.sh; its rules in modules/README.md §Evaluators).
# The lock files sit beside the evaluation lock in /etc/nix as tmpfiles `f`
# lines at 0444 root: they keep their inodes across activations, no user can
# truncate or replace them, and every user can flock a read-only descriptor.
# A /tmp path is removed by the /tmp age cleanup and can be created by anyone.
{ config, ... }:
let
  flakeLib = config.flake.lib;
in
{
  # Every NixOS host imports the capability; it is enabled wherever the host
  # evaluation lock is, the hosts whose memory class the host table knows.
  flake.modules.nixos.nix-build-lock =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.nixBuildLock;
    in
    {
      options.services.nixBuildLock = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = config.services.nixEvalLock.enable;
          defaultText = lib.literalExpression "config.services.nixEvalLock.enable";
          description = "Whether to install nix-build-locked, which runs a build under the host build lock and below the memory-pressure ceiling.";
        };

        lockFile = lib.mkOption {
          type = lib.types.str;
          default = "/etc/nix/build.lock";
          description = "Lock file nix-build-locked takes an exclusive flock on; its owner lock is this path with `.owner` appended.";
        };

        legacyLockFile = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "/tmp/build.lock";
          description = "A path sessions on this host take with flock(1) directly, made a root-owned symlink to lockFile so those sessions and nix-build-locked serialise on one lock; null for none.";
        };

        pressureThreshold = lib.mkOption {
          type = lib.types.ints.between 1 100;
          default = 20;
          description = "nix-build-locked starts a build only while some avg60 in /proc/pressure/memory is below this percentage.";
        };

        maxWait = lib.mkOption {
          type = lib.types.ints.unsigned;
          default = 3600;
          description = "Seconds nix-build-locked waits for the lock and for pressure to fall before it gives up with exit status 75 without running the build.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = flakeLib.mkNixBuildLockWrapper pkgs {
            inherit (cfg) lockFile pressureThreshold maxWait;
          };
          defaultText = lib.literalExpression "flake.lib.mkNixBuildLockWrapper pkgs { inherit (config.services.nixBuildLock) lockFile pressureThreshold maxWait; }";
          readOnly = true;
          description = "The nix-build-locked command installed on the system PATH.";
        };
      };

      config = lib.mkIf cfg.enable {
        systemd.tmpfiles.rules = [
          "f ${cfg.lockFile} 0444 root root -"
          "f ${cfg.lockFile}.owner 0444 root root -"
        ]
        ++ lib.optionals (cfg.legacyLockFile != null) [
          # `+` replaces a regular file a session created at the path before
          # it was managed; `x` keeps the /tmp age cleanup off the link.
          "L+ ${cfg.legacyLockFile} - - - - ${cfg.lockFile}"
          "x ${cfg.legacyLockFile}"
        ];

        environment.systemPackages = [ cfg.package ];
      };
    };
}
