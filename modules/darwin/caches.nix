# Binary cache configuration for darwin systems
# Merged into darwin.base via dendritic auto-discovery
# DRYed with lib/caches.nix (shared with flake.nix and system/caches.nix)
let
  # Shared cache configuration
  cacheConfig = import ../../lib/caches.nix;
in
{
  flake.modules = {
    darwin.base = {
      nix.settings.substituters = cacheConfig.substituters;
      nix.settings.trusted-public-keys = cacheConfig.publicKeys;
    };
  };
}
