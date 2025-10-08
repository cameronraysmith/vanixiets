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
in
packageOverrides
// {
  # Additional overrides
  # omnix = inputs.omnix.packages.${self.system}.default;
}
