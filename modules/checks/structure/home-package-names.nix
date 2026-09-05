# Pins the sorted package names of every homeConfigurations."<user>@<system>"
# on the current system to the committed golden, so that moving a declaration
# between aggregates cannot change what a user has installed unless the golden
# changes in the same commit.
#
# `lib.getName` rather than `name`: the golden pins what is installed, not the
# version nixpkgs currently ships, so a flake update leaves it valid.
# Only the current system's configurations are evaluated here; the golden holds
# every system's entries and `just home-package-names-golden` regenerates the
# current system's while keeping the others. Entries for another system are
# produced on a host of that system (some configurations import from
# derivations only that platform can realise); a configuration for this system
# with no golden entry fails the diff rather than being skipped.
{ self, lib, ... }:
let
  golden = builtins.fromJSON (builtins.readFile ./home-package-names.json);
  forSystem = system: lib.filterAttrs (key: _: lib.hasSuffix "@${system}" key);
in
{
  flake.lib.homePackageNames =
    system:
    lib.mapAttrs (
      _: home: builtins.sort builtins.lessThan (map lib.getName home.config.home.packages)
    ) (forSystem system self.homeConfigurations);

  perSystem =
    { pkgs, system, ... }:
    {
      checks.structure-home-package-names = self.lib.mkStructuralCheck pkgs {
        name = "home-package-names";
        actual = self.lib.homePackageNames system;
        expected = forSystem system golden;
      };
    };
}
