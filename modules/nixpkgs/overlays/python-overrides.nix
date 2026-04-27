# Python package overrides
#
# Coupled because the python3 override and the python3Packages rebind must
# share a single override scope: the rebind `python3Packages = final.python3.pkgs`
# only sees the package set produced by this same override invocation.
#
# Future refactor: pygame and the duckdb cross-reference could migrate to
# `pythonPackagesExtensions ++ [ ... ]` (see modules/nixos/nvidia.nix), but
# the python3Packages rebind would still need to live somewhere — splitting
# further is out of scope here.
#
# Contained:
#   - pygame: SDL2 surface flag tests fail on Python 3.13
#     Upstream: https://github.com/libsdl-org/SDL/issues/14424
#     Failing: test_fill_rle, test_make_surface__subclassed_surface
#     TODO: Remove when nixpkgs skip-rle-tests.patch covers these tests
#     Date added: 2026-01-24
#
#   - duckdb cross-reference: route python3Packages.duckdb through the by-name
#     python-duckdb package (pkgs/by-name/python-duckdb/), which has tests
#     disabled and tracks the by-name C++ duckdb version. On machines (via
#     compose.nix), final.python-duckdb exists because customPackages are
#     merged into the overlay scope. In perSystem context it doesn't exist,
#     so fall back to nixpkgs' version.
#     Update both packages: nix run .#update-duckdb
{ ... }:
{
  nixpkgsOverlays = [
    (final: prev: {
      python3 = prev.python3.override {
        packageOverrides = pyFinal: pyPrev: {
          pygame = pyPrev.pygame.overrideAttrs {
            doCheck = false;
            doInstallCheck = false;
          };

          duckdb = final.python-duckdb or pyPrev.duckdb;
        };
      };
      python3Packages = final.python3.pkgs;
    })
  ];
}
