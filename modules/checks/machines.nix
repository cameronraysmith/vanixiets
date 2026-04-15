# Machine toplevel build-realization checks.
#
# Wires each nixosConfigurations toplevel as a flake check so CI exercises the
# full build closure for every registered machine. Follows ironstar's
# package-as-check inheritance idiom (modules/rust.nix:249-251): bind the
# already-built derivation directly without a wrapper.
#
# Phase 1 (nix-144.1) covers x86_64-linux nixos machines only. Darwin machines
# defer to Phase 2 (nix-144.3) when aarch64-darwin runners are available.
# scheelite defers pending the GPU/CUDA binary cache readiness (see
# project_scheelite-gpu-deployment memory; coverage-map Q4).
{ self, lib, ... }:
{
  perSystem =
    { system, ... }:
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        vanixiets-nixos-cinnabar = self.nixosConfigurations.cinnabar.config.system.build.toplevel;
        vanixiets-nixos-electrum = self.nixosConfigurations.electrum.config.system.build.toplevel;
        vanixiets-nixos-galena = self.nixosConfigurations.galena.config.system.build.toplevel;
        vanixiets-nixos-magnetite = self.nixosConfigurations.magnetite.config.system.build.toplevel;
      };
    };
}
