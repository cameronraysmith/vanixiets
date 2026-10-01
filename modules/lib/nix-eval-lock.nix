# mkNixEvalLockWrapper: a `nix-eval-jobs` that serialises evaluations on a
# host behind a host-wide flock and offers itself to the OOM killer first. The
# behaviour lives in nix-eval-lock.sh; the NixOS capability that installs it
# is modules/nixos/nix-eval-lock.nix, and
# modules/checks/nix-eval-lock-rehearsal.nix runs it against a stub evaluator.
#
# `evaluator` is the path of the real binary and `lockFile` the lock.
# wrapNixEvalJobsWithLock wraps a package and keeps what its consumers read
# off it: the version (buildbot-nix asserts a minimum) and the `nix` passthru
# (nixbot puts the patched nix CLI matching its evaluator on the service PATH
# and links its own package against it).
{ lib, ... }:
let
  mkNixEvalLockWrapper =
    pkgs:
    {
      evaluator,
      lockFile,
      passthru ? { },
    }:
    pkgs.writeShellApplication {
      name = "nix-eval-jobs";
      runtimeInputs = [
        pkgs.coreutils
        (lib.getBin pkgs.util-linux)
      ]
      ++ lib.optional pkgs.stdenv.hostPlatform.isLinux pkgs.procps;
      text = ''
        lock_file=${lib.escapeShellArg lockFile}
        evaluator=${lib.escapeShellArg evaluator}
      ''
      + builtins.readFile ./nix-eval-lock.sh;
      inherit passthru;
    };
in
{
  flake.lib = {
    inherit mkNixEvalLockWrapper;

    wrapNixEvalJobsWithLock =
      pkgs: lockFile: package:
      mkNixEvalLockWrapper pkgs {
        evaluator = lib.getExe' package "nix-eval-jobs";
        inherit lockFile;
        passthru = {
          inherit (package) version;
          unwrapped = package;
        }
        // lib.optionalAttrs (package ? nix) { inherit (package) nix; };
      };
  };
}
