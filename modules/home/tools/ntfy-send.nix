# ntfy-send: post a push notification via ntfy.zt.
# Installs the by-name writeShellApplication (pkgs/by-name/ntfy-send/), which
# system units also run, so it lives beside the other package-install modules
# here, not under tools/commands/ (inline in-tree commands).
{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.ntfy-send ];
    };
}
