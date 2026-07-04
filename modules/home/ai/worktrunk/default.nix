{ ... }:
{
  flake.modules.homeManager.ai =
    { pkgs, flake, ... }:
    {
      imports = [ flake.inputs.worktrunk.homeModules.default ];
      programs.worktrunk = {
        enable = true;
        package = pkgs.worktrunk-bin;
      };
    };
}
