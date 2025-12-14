# macOS Window Manager (Stage Manager) settings
{ ... }:
{
  flake.modules.darwin.base =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      system.defaults = {
        # Window Manager (Stage Manager) settings
        WindowManager = {
          AppWindowGroupingBehavior = true;
          AutoHide = false;
          EnableStandardClickToShowDesktop = false;
          EnableTiledWindowMargins = false;
          GloballyEnabled = false;
          HideDesktop = false;
          StageManagerHideWidgets = false;
          StandardHideDesktopIcons = false;
          StandardHideWidgets = false;
        };
      };
    };
}
