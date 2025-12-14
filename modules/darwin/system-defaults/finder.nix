# macOS finder settings
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
      system.defaults.finder = {
        _FXShowPosixPathInTitle = false;
        _FXSortFoldersFirst = false;
        AppleShowAllExtensions = true;
        AppleShowAllFiles = false;
        CreateDesktop = true;
        FXDefaultSearchScope = "SCcf"; # Search current folder
        FXEnableExtensionChangeWarning = false;
        FXPreferredViewStyle = "Nlsv"; # List view
        QuitMenuItem = false;
        ShowPathbar = true;
        ShowStatusBar = false;
      };
    };
}
