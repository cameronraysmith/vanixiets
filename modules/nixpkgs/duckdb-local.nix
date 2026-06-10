{ lib, ... }:
let
  # Flipping this to false restores upstream nixpkgs duckdb/python-duckdb on
  # machines while the local derivations remain built by CI via the packages output.
  useLocalDuckdb = true;
in
{
  customPackageExcludes = lib.optionals (!useLocalDuckdb) [
    "duckdb"
    "python-duckdb"
  ];
}
