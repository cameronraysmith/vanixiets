# macOS input device settings (trackpad and magic mouse)
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
        # Magic Mouse settings
        magicmouse = {
          MouseButtonMode = "OneButton";
        };

        # Trackpad settings
        trackpad = {
          ActuationStrength = 1;
          Clicking = true;
          Dragging = true;
          FirstClickThreshold = 1;
          SecondClickThreshold = 2;
          TrackpadRightClick = true;
          TrackpadThreeFingerDrag = false;
          TrackpadThreeFingerTapGesture = 0;
        };
      };
    };
}
