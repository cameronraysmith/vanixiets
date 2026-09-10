{ config, ... }:
{
  flake.lib.linearSkillDirs = pkgs: [ "${pkgs.linear-cli.src}/skills" ];

  flake.modules.homeManager.linear = { pkgs, ... }: {
    home.packages = [ pkgs.linear-cli ];
    aiSkills.extraSkillDirs = config.flake.lib.linearSkillDirs pkgs;
  };
}
