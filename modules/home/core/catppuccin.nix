# Catppuccin theme configuration
# Extracted from vanixiets/modules/home/all/terminal/default.nix lines 302-303
{ inputs, ... }:
{
  # Two aggregates need the upstream module: `core` sets the global theme
  # below, and `shell/tmux.nix` sets `catppuccin.tmux`. Importing the same
  # attrset module from both files applies it twice, because the module system
  # deduplicates on `key` and an anonymous import is assigned a fresh one, and
  # the second application redefines the tmux plugin. Exporting one value with
  # an explicit key makes the two imports collapse into one.
  #
  # Every importer states its enrollment choice, because the upstream module
  # warns until `catppuccin.autoEnable` carries a definition at any priority
  # other than the option default's 1500 (<catppuccin>/modules/global.nix:20,
  # 92). mkDefault is priority 1000, so it silences the warning while `core`'s
  # normal-priority `true` below still wins.
  flake.lib.catppuccinHomeModule = {
    key = "vanixiets/catppuccin-home-module";
    imports = [
      inputs.catppuccin.homeModules.catppuccin
      (
        { config, lib, ... }:
        {
          catppuccin.autoEnable = lib.mkDefault config.catppuccin.enable;
        }
      )
    ];
  };

  flake.modules.homeManager.core =
    { flake, ... }:
    {
      imports = [ flake.lib.catppuccinHomeModule ];

      # Global catppuccin theme enable
      # Individual programs (tmux, bat, etc.) will use this theme automatically
      catppuccin = {
        enable = true;
        autoEnable = true;
        flavor = "mocha";

        # The default sources are build outputs read at evaluation (IFD);
        # the same upstream revs' committed themes/ come from flake inputs.
        sources = {
          bottom = "${inputs.catppuccin-bottom}/themes";
          starship = "${inputs.catppuccin-starship}/themes";
        };
      };
    };
}
