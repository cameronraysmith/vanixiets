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

  allPackages = fromDirectory ./packages;

  # filter out debug packages
  packageOverrides = lib.filterAttrs (name: _value: !(lib.hasSuffix "Debug" name)) allPackages;
in
packageOverrides
// {
  # Additional overrides
  # omnix = inputs.omnix.packages.${self.system}.default;
}
