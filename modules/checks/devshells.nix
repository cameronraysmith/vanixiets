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
    { self', ... }:
    {
      checks = lib.mapAttrs' (name: shell: lib.nameValuePair "devshell-${name}" shell) self'.devShells;
    };
}
