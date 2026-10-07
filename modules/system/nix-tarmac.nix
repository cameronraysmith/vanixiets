{ inputs, ... }:
{
  # Replaces the builtin tarball fetcher with a content-addressed cache, so tarball
  # flake inputs are not unpacked into the never-collected tarball-cache-v2 git repository.
  #
  # NixOS only: the loader probes with dlopen(bare_soname, RTLD_NOLOAD), which matches the
  # name a library was loaded under. Darwin nix records an absolute store path as its
  # install name, so the probe never matches and every nix invocation warns and falls back.
  flake.modules.nixos.base.imports = [ inputs.nix-tarmac.nixosModules.default ];
}
