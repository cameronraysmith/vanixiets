# repo-sync: conservatively fetch/fast-forward git and jj repositories under given paths.
# Installs the by-name writeShellApplication (pkgs/by-name/repo-sync/), so it lives
# beside the other package-install modules here, not under tools/commands/ (inline in-tree commands).
{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.repo-sync ];
    };
}
