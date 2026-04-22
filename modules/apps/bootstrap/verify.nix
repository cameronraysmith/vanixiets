# Flake app: verify the host's nix + flakes + direnv + devShell setup.
#
# Usage:
#   nix run .#verify           # full status report; exit nonzero on missing nix/flakes
#   nix run .#verify -- --help
#
# Chicken-and-egg note: Mirrors `make verify` from the repo-root Makefile.
# The Makefile version is callable from a nix-free shell (it's plain
# make + shell). This flake-app version assumes nix is already installed
# (since `nix run` requires nix); it exists so scripted contexts (CI,
# post-bootstrap sanity checks, buildbot effects) can invoke the audit
# without depending on GNU make being on PATH.
#
# Idempotent / pure: only reads state. Writes nothing; touches no files.
#
# Template bifurcation (writeShellApplication): PURE READFILE FORM.
# The sidecar needs no nix-eval-time path injection.
{ ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    {
      apps.verify = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "verify";
            runtimeInputs = [
              pkgs.bash
              pkgs.coreutils
              pkgs.gnugrep
              pkgs.nix
            ];
            text = builtins.readFile ./verify.sh;
          }
        );
      };
    };
}
