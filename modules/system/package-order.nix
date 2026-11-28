# The system path and the home profile list their packages sorted by name, and
# the Brewfile its taps, brews and casks by name, so where a module sits in the
# import tree does not decide their order. Entries with the same name keep
# their definition order: the sort is stable, and with no tie-break by store
# path a nixpkgs bump cannot change which of two same-named packages comes
# first and so wins an equal-priority collision. The Brewfile is written one
# section per kind, so sorting within a kind cannot move a tap after the cask
# that needs it.
{ lib, ... }:
let
  # types.package also admits a store path string with context, which is not
  # a derivation and has no name.
  packageName = p: if lib.isDerivation p then lib.getName p else toString p;
  byName = a: b: packageName a < packageName b;
  sortPackages = {
    options.environment.systemPackages = lib.mkOption { apply = lib.sort byName; };
  };
  # Entries arrive as submodules; a string entry is coerced to { name = ...; }.
  sortBrewfileList = lib.mkOption { apply = lib.sort (a: b: a.name < b.name); };
in
{
  flake.modules.nixos.base-package-order = sortPackages;
  flake.modules.darwin.base-package-order = {
    imports = [ sortPackages ];
    options.homebrew = {
      taps = sortBrewfileList;
      brews = sortBrewfileList;
      casks = sortBrewfileList;
    };
  };
  flake.modules.homeManager.package-order = {
    options.home.packages = lib.mkOption { apply = lib.sort byName; };
  };
}
