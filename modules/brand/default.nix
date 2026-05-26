# Brand assets exposed at the flake level for consumption by NixOS / home-manager modules.
{ lib, ... }:
{
  options.flake.brand = {
    logo = lib.mkOption {
      type = lib.types.path;
      description = "Path to the canonical brand logo (SVG) for site-level branding.";
    };
  };

  config.flake.brand = {
    logo = ./assets/logo.svg;
  };
}
