let
  # Shared cache configuration (DRY with flake.nix and darwin/caches.nix)
  cacheConfig = import ../../lib/caches.nix;
in
{
  # Shared nix caches and substituters configuration
  # Auto-merges into base namespace for both darwin and nixos
  flake.modules.darwin.base = {
    nix.settings.substituters = cacheConfig.substituters;
    nix.settings.trusted-public-keys = cacheConfig.publicKeys;
  };

  flake.modules.nixos.base = {
    nix.settings.substituters = cacheConfig.substituters;
    nix.settings.trusted-public-keys = cacheConfig.publicKeys;
  };
}
