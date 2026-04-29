# Atuin history formatter (nushell-based)
# Independent package install — not a writeShellApplication, so it lives
# alongside the per-tool modules under modules/home/tools/ rather than
# under commands/ which is reserved for shell-script-based commands.
{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.atuin-format ];
    };
}
