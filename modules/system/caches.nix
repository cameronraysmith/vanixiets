let
  # Shared cache configuration (kept in sync with flake.nix's nixConfig)
  cacheConfig = import ../../lib/caches.nix;
in
{
  # The one writer of the fleet's binary caches into nix.settings for both
  # classes; a second definition would list each cache twice in nix.conf.
  flake.modules.darwin.base = {
    nix.settings.substituters = cacheConfig.substituters;
    nix.settings.trusted-public-keys = cacheConfig.publicKeys;
  };

  flake.modules.nixos.base = {
    nix.settings.substituters = cacheConfig.substituters;
    nix.settings.trusted-public-keys = cacheConfig.publicKeys;
  };
}
