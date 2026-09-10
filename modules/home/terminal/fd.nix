{ ... }:
let
  content =
    { ... }:
    {
      programs.fd.enable = true;
    };
in
{
  flake.modules.homeManager.terminal = content;
  flake.modules.homeManager.fd = content;
}
