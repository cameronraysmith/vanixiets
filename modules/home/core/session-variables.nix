# Session environment variables
# Extracted from vanixiets/modules/home/all/terminal/default.nix lines 294-299
{ ... }:
{
  flake.modules.homeManager.core =
    { ... }:
    {
      home.sessionVariables = {
        EDITOR = "nvim";
        LANG = "en_US.UTF-8";
        LC_ALL = "en_US.UTF-8";
        LC_CTYPE = "en_US.UTF-8";
      };
    };
}
