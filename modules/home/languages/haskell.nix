{ ... }:
{
  flake.modules.homeManager.languages =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        ghc
        cabal-install
      ];
    };
}
