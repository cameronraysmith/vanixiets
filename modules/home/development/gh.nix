{ ... }:
let
  content =
    personal:
    { pkgs, ... }:
    {
      programs.gh = {
        enable = true;
        extensions = [ pkgs.gh-stack ];
        gitCredentialHelper.enable = !personal;
      };
    };
in
{
  flake.modules.homeManager.development = content true;
  flake.modules.homeManager.gh = content false;
}
