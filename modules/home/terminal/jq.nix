{ ... }:
let
  content =
    { ... }:
    {
      programs.jq.enable = true;
    };
in
{
  flake.modules.homeManager.terminal = content;
  flake.modules.homeManager.jq = content;
}
