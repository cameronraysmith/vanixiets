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
    { self', system, ... }:
    let
      blacklist = [
        # evaluation needs import-from-derivation
        "k8s-manifests-local-json"
        "k8s-manifests-local-k3d-json"
        # already exposed under existing check names
        "fdContainer-aarch64"
        "fdContainer-x86_64"
        "rgContainer-aarch64"
        "rgContainer-x86_64"
        # built by checks.x86_64-linux.skills-marketplace-drift only; its output
        # does not depend on the platform (design D8, skills-single-source-marketplaces)
        "skills-marketplace"
        # run by checks.x86_64-linux.skills-spec-conformance, whose output names
        # it so that the check's upload carries it to the cache
        # (skills-single-source-marketplaces D15)
        "skill-validator"
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
      checks =
        lib.mapAttrs' (n: lib.nameValuePair "package-${n}") filtered
        # The compose copies its remote dependencies from this fixed-output
        # derivation at build time only, so no package's upload carries it; one
        # path on every system, exposed once.
        // lib.optionalAttrs (system == "x86_64-linux") {
          apm-deps = self'.packages.apm-skills-compose.deps;
        };
    };
}
