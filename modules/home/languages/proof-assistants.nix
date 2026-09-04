{ ... }:
{
  flake.modules.homeManager.languages =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        idris2
        idris2Packages.idris2Lsp
        rocq-core
      ];
    };
}
