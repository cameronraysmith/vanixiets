{ ... }:
{
  flake.modules.homeManager.development =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        noto-fonts-color-emoji
        fira-code
        cascadia-code
        monaspace
        nerd-fonts.monaspace
        inconsolata
        nerd-fonts.inconsolata
      ];
    };
}
