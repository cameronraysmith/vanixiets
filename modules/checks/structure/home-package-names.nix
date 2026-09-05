# Pins the sorted package names of every homeConfigurations."<user>@<system>"
# on the current system to the committed golden, so that moving a declaration
# between aggregates cannot add or remove a package name from any user's set
# unless the golden file changes in the same commit.
#
# Names come from `lib.getName` (the pname, not the versioned `name`), so a
# flake update leaves the golden valid; for the same reason a version change,
# a wrapper standing in for the raw package of the same name, or a changed
# override passes unchanged.
# Only the current system's configurations are evaluated here; the golden
# holds every system's entries. `just home-package-names-golden` evaluates
# every configuration for one system and replaces that system's entries. A
# configuration that imports from a derivation (today `crs58` and `cameron`
# on aarch64-darwin and aarch64-linux, via `apm-skills-compose` in the `ai`
# aggregate) can only be evaluated by a host that can realise it, so its entry
# is produced on such a host. A configuration for this system with no golden
# entry fails the diff rather than being skipped.
{ self, lib, ... }:
let
  golden = builtins.fromJSON (builtins.readFile ./home-package-names.json);
in
{
  perSystem =
    { pkgs, system, ... }:
    {
      checks.structure-home-package-names = self.lib.mkStructuralCheck pkgs {
        name = "home-package-names";
        actual = self.lib.homePackageNames system;
        expected = lib.filterAttrs (key: _: lib.hasSuffix "@${system}" key) golden;
      };
    };
}
