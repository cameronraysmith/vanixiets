# macOS screenshot settings
{ ... }:
{
  flake.modules.darwin.base-system-defaults =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      system.defaults = {
        # Screenshot settings
        screencapture = {
          disable-shadow = true;
          location = "~/Downloads";
          show-thumbnail = true;
          type = "png";
          target = "file";
        };
      };
    };
}
