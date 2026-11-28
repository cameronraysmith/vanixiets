# nuenv overlay integration
#
# Provides nushell script packaging utilities and improvements to nixpkgs.
# Key exports include nuenv.writeShellApplication, nuenv.writeScript, and
# nuenv.mkNushellScript for convenient nushell application packaging.
#
{ inputs, ... }:
{
  nixpkgsOverlaysByName.nuenv = [
    inputs.nuenv.overlays.nuenv
  ];
}
