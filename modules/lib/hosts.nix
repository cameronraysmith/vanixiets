# Per-host ZeroTier-address registry, the canonical source of truth for mesh
# addresses consumed across NixOS, home-manager, and terranix evals.
# Consolidated into this single file because flake.lib is lazyAttrsOf raw,
# which forbids multi-file writes at the same nested path.
{ ... }:
{
  flake.lib.hosts = {
    magnetite.zt = "fddb:4344:343b:14b9:399:930f:39db:40d2";
  };
}
