# Base sops profile.
#
# Bundles the sops-nix home-manager integration aggregated under
# `flake.modules.homeManager.base-sops`, which configures the
# `sops.age.keyFile` location and age plugins for clan-managed secret
# decryption. Declared as a typed entry under `flake.profiles.homeManager`
# (registered by `modules/lib/profiles.nix`).
{ config, lib, ... }:
{
  flake.profiles.homeManager.base-sops = {
    description = "Sops-nix integration providing age-key location and plugins for clan-managed secret decryption.";
    includes = [ config.flake.modules.homeManager.base-sops ];
  };
}
