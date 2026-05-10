# Per-package passthru.tests build-realization checks.
#
# Iterates self'.packages and exposes each pkg.passthru.tests.<tname> as
# package-${pname}-test-${tname}. Free coverage for any package that
# declares passthru.tests in the standard nixpkgs convention.
#
# Shares the packages.nix blacklist to avoid duplicating tests already
# exposed under another check name (notably vanixiets-docs's
# {e2e,linkcheck,unit} which land as docs-{e2e,linkcheck,unit} via
# modules/checks/docs.nix).
{ lib, ... }:
{
  perSystem =
    { self', ... }:
    let
      blacklist = [
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
        "fdManifest"
        "fdManifest-aarch64"
        "fdManifest-x86_64"
        "rgManifest"
        "rgManifest-aarch64"
        "rgManifest-x86_64"
        "nix-fast-build"
      ];

      filtered = lib.filterAttrs (n: _v: !(builtins.elem n blacklist)) self'.packages;
    in
    {
      checks = lib.concatMapAttrs (
        pname: pkg:
        lib.mapAttrs' (tname: lib.nameValuePair "package-${pname}-test-${tname}") (
          pkg.passthru.tests or { }
        )
      ) filtered;
    };
}
