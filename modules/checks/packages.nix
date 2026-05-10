# Per-package build-realization checks.
#
# Mic92-style mapAttrs' over self'.packages with a blacklist for entries
# that are already covered under another check name, are intentional
# effect-input-wires (impure pushes), or are thin upstream re-packages
# fully cache-resident on cache.nixos.org without first-party patches.
#
# Naming: package-${n} (category prefix; ecosystem standard per mic92,
# clan-infra). No vanixiets- prefix (provenance is implicit via repo).
{ lib, ... }:
{
  perSystem =
    { self', ... }:
    let
      blacklist = [
        # already exposed under existing check names
        "vanixiets-docs"
        "vanixiets-docs-deps"
        "k8s-manifests-local"
        "k8s-manifests-local-json"
        "k8s-manifests-local-k3d"
        "k8s-manifests-local-k3d-json"
        "fdContainer-aarch64"
        "fdContainer-x86_64"
        "rgContainer-aarch64"
        "rgContainer-x86_64"
        # intentional effect-input-wires (impure ghcr.io push)
        "fdManifest"
        "fdManifest-aarch64"
        "fdManifest-x86_64"
        "rgManifest"
        "rgManifest-aarch64"
        "rgManifest-x86_64"
        # thin upstream re-package, fully cache-resident on cache.nixos.org
        "nix-fast-build"
      ];

      filtered = lib.filterAttrs (n: _v: !(builtins.elem n blacklist)) self'.packages;
    in
    {
      checks = lib.mapAttrs' (n: lib.nameValuePair "package-${n}") filtered;
    };
}
