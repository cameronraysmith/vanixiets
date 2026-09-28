{ ... }:
{
  flake.modules.homeManager.playwright-cli =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.playwright-cli ];
    };
}
