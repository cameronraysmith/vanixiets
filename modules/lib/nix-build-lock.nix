# mkNixBuildLockWrapper: `nix-build-locked COMMAND...`, which runs COMMAND as
# the host's one build at a time and only while memory pressure is below a
# ceiling. The behaviour lives in nix-build-lock.sh; the NixOS capability that
# installs it is modules/nixos/nix-build-lock.nix, and
# modules/checks/nix-build-lock-rehearsal.nix runs it against a stub build.
{ lib, ... }:
{
  flake.lib.mkNixBuildLockWrapper =
    pkgs:
    {
      lockFile,
      pressureThreshold,
      maxWait,
      pressureFile ? "/proc/pressure/memory",
      reportInterval ? 30,
    }:
    pkgs.writeShellApplication {
      name = "nix-build-locked";
      runtimeInputs = [
        pkgs.coreutils
        (lib.getBin pkgs.util-linux)
        pkgs.procps
      ];
      text = ''
        lock_file=${lib.escapeShellArg lockFile}
        pressure_file=${lib.escapeShellArg pressureFile}
        pressure_threshold=${toString pressureThreshold}
        max_wait=${toString maxWait}
        report_interval=${toString reportInterval}
      ''
      + builtins.readFile ./lock-holder.sh
      + builtins.readFile ./nix-build-lock.sh;
    };
}
