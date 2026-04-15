# Nixidy-rendered kubernetes manifest and environment build-realization checks.
#
# Coverage map finding: nixidy and easykubenix are independent bridges; nixidy
# is not transitively covered by the k8s-manifests packages. Both the generated
# manifests and the nixidy env derivations are leaf outputs with no ancestor
# check, so each is bound individually following ironstar's package-as-check
# idiom (modules/rust.nix:249-251).
#
# Binds four manifest packages plus the two nixidy env derivations
# (environmentPackage and bootstrapPackage) across the three systems where
# nixidyEnvs and the manifest packages are exposed: aarch64-darwin,
# aarch64-linux, x86_64-linux.
{ self, lib, ... }:
{
  perSystem =
    {
      self',
      system,
      ...
    }:
    let
      exposedSystems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
    in
    {
      checks = lib.optionalAttrs (lib.elem system exposedSystems) {
        inherit (self'.packages)
          k8s-manifests-local
          k8s-manifests-local-json
          k8s-manifests-local-k3d
          k8s-manifests-local-k3d-json
          ;
        nixidy-env-local-k3d = self.nixidyEnvs.${system}.local-k3d.environmentPackage;
        nixidy-bootstrap-local-k3d = self.nixidyEnvs.${system}.local-k3d.bootstrapPackage;
      };
    };
}
