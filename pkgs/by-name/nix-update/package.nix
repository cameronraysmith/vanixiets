# nix-update 1.17.0 over the locked nixpkgs' 1.16.0, for realize-pin's
# FixedOutputHasher. 1.16.0 cannot hash a flake attribute with nix 2.35.6: it
# reads the flake's store path from `nix flake metadata --json` without the
# flake being copied there, and fails opening it. 1.17.0 copies the flake with
# `nix flake prefetch` (upstream dcef4fd).
#
# Temporary, and the assertion below keeps it so: once the locked nixpkgs
# carries nix-update 1.17.0 or later, evaluating this package fails, and this
# package, its size entries in modules/checks/packages.nix and the
# customPackageExcludes entry in modules/apps/realize-pin.nix are deleted.
#
# nixpkgs' own definition is called by path: the name `nix-update` in this
# scope is this package, so taking it as an argument recurses.
{
  lib,
  path,
  callPackage,
  fetchFromGitHub,
  python3Packages,
}:
let
  nixpkgsNixUpdate = callPackage (path + "/pkgs/by-name/ni/nix-update/package.nix") { };
in
assert lib.assertMsg (lib.versionOlder nixpkgsNixUpdate.version "1.17.0") ''
  nixpkgs now carries nix-update ${nixpkgsNixUpdate.version}: delete pkgs/by-name/nix-update,
  its package-nix-update entries in modules/checks/packages.nix and the
  customPackageExcludes entry in modules/apps/realize-pin.nix.
'';
nixpkgsNixUpdate.overridePythonAttrs (old: {
  version = "1.17.0";

  src = fetchFromGitHub {
    owner = "Mic92";
    repo = "nix-update";
    tag = "v1.17.0";
    hash = "sha256-TCOhUWb53V3nrJRD3JuADly1U9fNi0Z79QMcjhbefHg=";
  };

  build-system = [ python3Packages.hatchling ];

  dependencies = (old.dependencies or [ ]) ++ [ python3Packages.ast-grep-py ];

  meta = old.meta // {
    description = "Swiss-knife for updating nix packages (1.17.0, temporary until nixpkgs reaches it)";
  };
})
