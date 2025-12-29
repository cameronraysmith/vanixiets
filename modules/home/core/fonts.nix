# Font configuration
# Extracted from vanixiets/modules/home/all/terminal/default.nix line 301
{ ... }:
{
  flake.modules.homeManager.core =
    { ... }:
    {
      fonts.fontconfig.enable = true;
    };
}
