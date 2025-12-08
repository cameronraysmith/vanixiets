# Packages aggregate directory marker
# Individual modules in packages/ are auto-discovered by import-tree
# and merged into homeManager.packages aggregate namespace
{ ... }:
{
  # Namespace stub for import-tree aggregate discovery
  # All configuration in packages/*.nix files:
  # - terminal.nix (unix tools, fonts)
  # - development.nix (dev tools, languages)
  # - compute.nix (cloud/k8s tools)
  # - security.nix (security tools)
  # - database.nix (database tools)
  # - publishing.nix (publishing tools)
  # - shell-aliases.nix (shell aliases)
  flake.modules.homeManager.packages = { ... }: { };
}
