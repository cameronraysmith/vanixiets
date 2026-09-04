{ ... }:
{
  flake.modules.homeManager.languages =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        ocaml
        dune_3
        opam
      ];
    };
}
