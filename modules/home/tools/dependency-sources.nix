# dependency-sources: git-forge source URLs of a workspace's declared deps, for `ghq get`.
# Installs the by-name writeShellApplication (pkgs/by-name/dependency-sources/), so it lives
# beside the other package-install modules here, not under tools/commands/ (inline in-tree commands).
{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.dependency-sources ];
    };
}
