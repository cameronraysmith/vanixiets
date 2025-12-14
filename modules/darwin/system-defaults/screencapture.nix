# macOS screenshot settings
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
