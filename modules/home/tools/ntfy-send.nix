# ntfy-send: post a push notification to the fleet's ntfy, at
# ntfy.vanixiets.internal on a Mac and ntfy.zt on NixOS.
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
