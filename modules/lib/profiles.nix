# Typed profile registry namespace.
#
# Declares `options.flake.profiles` as a two-level typed registry keyed
# first by class (`homeManager`, future `nixos`, etc.) and then by
# bundle name. Each bundle is a submodule with `description` and
# `includes` fields. Per-bundle-per-file authoring is supported because
# `lazyAttrsOf submodule` recurses into nested option declarations and
# merges values written at the same path from multiple modules — the
# constraint that forced the previous `flake.lib.profiles` registry
# into a single consolidated module no longer applies once the registry
# moves out of `flake.lib` (which is `lazyAttrsOf raw`).
#
# `flake.lib.profileType` is co-located here as the submodule reference
# used by the consumer option `flake.users.<u>.profiles`.
{ lib, ... }:
let
  profileSubmodule = lib.types.submodule {
    options = {
      description = lib.mkOption {
        type = lib.types.str;
        description = "One-line summary of what this profile composes.";
      };
      includes = lib.mkOption {
        type = lib.types.listOf lib.types.deferredModule;
        description = "List of deferred modules this profile bundles.";
      };
    };
  };
in
{
  options.flake.profiles = lib.mkOption {
    type = lib.types.lazyAttrsOf (lib.types.lazyAttrsOf profileSubmodule);
    default = { };
    description = ''
      Typed profile registry keyed first by module class
      (`homeManager`, future `nixos`, etc.) and then by bundle name.
      Each bundle declares `description` and `includes`. Reference by
      attribute access against `config.flake.profiles.<class>`.
    '';
  };
}
