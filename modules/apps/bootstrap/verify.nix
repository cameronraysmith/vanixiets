# Flake app: verify the host's nix + flakes + direnv + devShell setup.
#
# Chicken-and-egg note: Mirrors `make verify` from the repo-root Makefile.
# The Makefile version is callable from a nix-free shell (it's plain
# make + shell). This flake-app version assumes nix is already installed
# (since `nix run` requires nix); it exists so scripted contexts (CI,
# post-bootstrap sanity checks, buildbot effects) can invoke the audit
# without depending on GNU make being on PATH.
#
# Read-only.
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
