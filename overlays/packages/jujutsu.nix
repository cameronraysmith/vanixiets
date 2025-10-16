{ pkgs, ... }:
# Export jujutsu overlay package for pre-caching in CI
#
# This ensures jujutsu (from inputs.jj) is built and cached by the
# cache-overlay-packages job before NixOS system builds run, preventing
# "No space left on device" errors when jujutsu gets built from source
# during system builds.
#
# The overlay in overlays/default.nix provides the custom jujutsu version:
#   jujutsu = inputs.jj.packages.${super.system}.jujutsu or super.jujutsu;
pkgs.jujutsu
