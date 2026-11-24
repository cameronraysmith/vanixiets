# DevShell build-realization checks.
#
# Binds each entry of self'.devShells as a flake check following the
# clan-infra direct-binding idiom (checks/flake-module.nix:61), using
# lib.mapAttrs' to rename each shell to "devshell-${name}". This realizes
# the shell closure under `nix flake check`, catching overlay drift and
# input-derivation breakage that no other check surfaces.
#
# Systems: aarch64-darwin, aarch64-linux, x86_64-linux
# Shells: default, kubernetes, terraform
{ lib, ... }:
{
  perSystem =
    { self', system, ... }:
    {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks =
        {
          x86_64-linux = {
            # nixbot: median 11 s, slowest 1865 s, 39 runs in 30 days
            devshell-default.class = "small";
            # nixbot: median 6.1 s, slowest 96 s, 4 runs in 30 days
            devshell-docs.class = "small";
            # nixbot: median 4.3 s, slowest 20 s, 3 runs in 30 days
            devshell-kubernetes.class = "small";
            # nixbot: median 12 s, slowest 80 s, 13 runs in 30 days
            devshell-terraform.class = "small";
          };
          aarch64-darwin = {
            # nixbot: median 19 s, slowest 532 s, 40 runs in 30 days
            devshell-default.class = "small";
            # nixbot: median 146 s, slowest 751 s, 4 runs in 30 days
            devshell-docs.class = "medium";
            # nixbot: median 90 s, slowest 270 s, 3 runs in 30 days
            devshell-kubernetes.class = "medium";
            # nixbot: median 111 s, slowest 682 s, 13 runs in 30 days
            devshell-terraform.class = "medium";
          };
        }
        .${system} or { };
      checks = lib.mapAttrs' (name: shell: lib.nameValuePair "devshell-${name}" shell) self'.devShells;
    };
}
