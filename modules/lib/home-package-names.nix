# homePackageNames: the sorted `lib.getName` of every `home.packages` entry,
# keyed `user@system`, for the homeConfigurations of one system.
# Shared by `checks.structure-home-package-names` and the
# `just home-package-names-golden` recipe, so both read the same names.
{ self, lib, ... }:
{
  flake.lib.homePackageNames =
    system:
    lib.mapAttrs (
      _: home: builtins.sort builtins.lessThan (map lib.getName home.config.home.packages)
    ) (lib.filterAttrs (key: _: lib.hasSuffix "@${system}" key) self.homeConfigurations);
}
