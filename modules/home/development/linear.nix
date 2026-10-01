{ config, ... }:
{
  flake.lib.linearSkills = pkgs: { linear-cli = "${pkgs.linear-cli.src}/skills/linear-cli"; };

  flake.modules.homeManager.linear = { pkgs, ... }: {
    home.packages = [ pkgs.linear-cli ];
    aiSkills.extraSkills = config.flake.lib.linearSkills pkgs;
  };
}
