{ flake, ... }:

self: super:
let
  inherit (super) lib;

  fromDirectory =
    directory:
    lib.packagesFromDirectoryRecursive {
      callPackage = lib.callPackageWith self;
      inherit directory;
    };

  packageOverrides = fromDirectory ./packages;
  packageDebugging = fromDirectory ./debug;
in
packageOverrides
// {
  # Debug packages for nixpkgs maintenance (doesn't override nixpkgs)
  inherit packageDebugging;

  # Additional overrides
  # omnix = inputs.omnix.packages.${self.system}.default;
}
