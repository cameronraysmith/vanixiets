# Yazi terminal file manager with shell integrations
{ ... }:
{
  flake.modules = {
    homeManager.shell =
      {
        pkgs,
        config,
        lib,
        flake,
        ...
      }:
      {
        programs.yazi = {
          enable = true;
          enableBashIntegration = true;
          enableNushellIntegration = true;
          enableZshIntegration = true;
          settings = {
            preview.tab_size = 2;
            mgr = {
              show_hidden = true;
              show_symlink = true;
              sort_by = "natural";
              sort_dir_first = true;
            };
          };
        };
      };
  };
}
