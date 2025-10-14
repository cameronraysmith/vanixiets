# ghc_filesystem: disable test compilation due to clang 21.x compatibility issues
#
# Issue: Test suite fails to compile on darwin with clang 21.x due to:
#   -Werror,-Wcharacter-conversion
#   Implicit char16_t to char32_t conversion in toUtf8 function
#
# Root cause: Package's CMakeLists.txt doesn't respect -DBUILD_TESTING=OFF properly,
#   still compiles test targets which hit the clang error
#
# Fix: Explicitly set GHC_FILESYSTEM_BUILD_TESTING=OFF to prevent test compilation
#
# References:
#   - Error: https://github.com/gulrak/filesystem/blob/v1.5.14/include/ghc/filesystem.hpp#L1675
#   - Upstream issue: https://github.com/gulrak/filesystem/issues/29
#   - Hydra: https://hydra.nixos.org/job/nixpkgs/trunk/ghc_filesystem.aarch64-darwin
#
# TODO: Remove when either:
#   - Upstream fixes clang 21.x compatibility
#   - nixpkgs uses different clang version
#   - Package respects BUILD_TESTING flag properly
#
# Date added: 2025-10-13
# Updated: 2025-10-13 (fixed cmake flag)
# Affects: aarch64-darwin, x86_64-darwin
#
final: prev: {
  ghc_filesystem = prev.ghc_filesystem.overrideAttrs (oldAttrs: {
    # Disable test running
    doCheck = false;

    # Explicitly disable test compilation via package-specific cmake flag
    # This prevents CMake from compiling test targets that trigger clang errors
    cmakeFlags = (oldAttrs.cmakeFlags or [ ]) ++ [
      "-DGHC_FILESYSTEM_BUILD_TESTING=OFF"
      "-DGHC_FILESYSTEM_BUILD_EXAMPLES=OFF"
    ];
  });
}
