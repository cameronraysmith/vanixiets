# macOS login window settings
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
        # Login window settings
        loginwindow = {
          autoLoginUser = null;
          DisableConsoleAccess = false;
          GuestEnabled = false;
          LoginwindowText = null;
          PowerOffDisabledWhileLoggedIn = false;
          RestartDisabled = false;
          RestartDisabledWhileLoggedIn = false;
          SHOWFULLNAME = false;
          ShutDownDisabled = false;
          ShutDownDisabledWhileLoggedIn = false;
          SleepDisabled = false;
        };
      };
    };
}
