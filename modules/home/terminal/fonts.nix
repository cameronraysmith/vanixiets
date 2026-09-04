{ ... }:
{
  flake.modules.homeManager.terminal =
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
        # jetbrains-mono and nerd-fonts.jetbrains-mono installed via homebrew casks
      ];
    };
}
