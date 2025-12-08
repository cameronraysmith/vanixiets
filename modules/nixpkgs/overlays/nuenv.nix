# nuenv overlay integration
#
# Provides nushell script packaging utilities and improvements to nixpkgs.
# Key exports include nuenv.writeShellApplication, nuenv.writeScript, and
# nuenv.mkNushellScript for convenient nushell application packaging.
#
{ inputs, ... }:
{
  flake.nixpkgsOverlays = [
    inputs.nuenv.overlays.nuenv
  ];
}
