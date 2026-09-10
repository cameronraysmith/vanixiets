{ ... }:
let
  content =
    { ... }:
    {
      programs.ripgrep.enable = true;
    };
in
{
  flake.modules.homeManager.terminal = content;
  flake.modules.homeManager.ripgrep = content;
}
