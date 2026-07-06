# ghq-sync: lazy, partial-clone-aware ghq wrapper for the Category-2 reference tree.
# Installs the by-name writeShellApplication (pkgs/by-name/ghq-sync/), so it lives
# beside the other package-install modules here, not under tools/commands/ (inline in-tree commands).
{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.ghq-sync ];
    };
}
