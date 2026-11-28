{ ... }:
{
  flake.modules.homeManager.development =
    { lib, pkgs, ... }:
    {
      home.packages =
        with pkgs;
        [
          noto-fonts-color-emoji
          fira-code
          cascadia-code
          monaspace
          nerd-fonts.monaspace
          inconsolata
          nerd-fonts.inconsolata
        ]
        # The Macs take JetBrains Mono from the Homebrew casks in the base cask list.
        ++ lib.optionals stdenv.hostPlatform.isLinux [
          jetbrains-mono
          nerd-fonts.jetbrains-mono
        ];
    };
}
