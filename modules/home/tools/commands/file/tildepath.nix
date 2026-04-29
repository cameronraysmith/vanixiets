{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, config, ... }:
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "tildepath";
          runtimeInputs = with pkgs; [ coreutils ];
          text = ''
            export HM_HOME_DIR=${config.home.homeDirectory}
            ${builtins.readFile ./tildepath.sh}
          '';
          meta.description = "Resolve path to absolute form with tilde expansion for home directory";
        })
      ];
    };
}
