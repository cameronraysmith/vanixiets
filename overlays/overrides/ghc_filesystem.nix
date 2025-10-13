# ghc_filesystem: disable tests due to clang 21.x compilation issues
#
# Issue: Test suite fails on darwin with clang 21.x due to:
#   -Werror,-Wcharacter-conversion
#   Implicit char16_t to char32_t conversion in toUtf8 function
#
# Reference: https://github.com/gulrak/filesystem/blob/v1.5.14/include/ghc/filesystem.hpp#L1675
#
# TODO: Monitor upstream for fix or clang version change, then remove this override
#
# Date added: 2025-10-13
# Affects: aarch64-darwin, x86_64-darwin
#
final: prev: {
  ghc_filesystem = prev.ghc_filesystem.overrideAttrs (oldAttrs: {
    doCheck = false;
  });
}
