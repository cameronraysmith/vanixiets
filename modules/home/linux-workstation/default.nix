# GUI applications for a graphical Linux home. Only hosts with a graphical
# session import this module; headless homes never do, so it may assume a
# display server, a desktop-entry consumer and Linux-only packages.
{ ... }:
{
  flake.modules.homeManager.linux-workstation =
    { pkgs, flake, ... }:
    let
      inherit (pkgs.stdenv.hostPlatform) system;
      antigravity-hub = flake.inputs.llm-agents.packages.${system}.antigravity-hub;
    in
    {
      # The development aggregate leaves the package null for headless homes
      # and for the Macs, which take Zed from the zed Homebrew cask in the
      # darwin base cask list. The FHS variant runs the language servers and
      # agent binaries Zed downloads. Its command stays `zeditor`: on a ZFS host
      # `zed` is the ZFS event daemon on the system PATH.
      programs.zed-editor.package = pkgs.zed-editor.fhs;
      programs.calibre.enable = true;
      # Zathura, themed by catppuccin.zathura, is the LaTeX preview and
      # presentation viewer; Papers stays the default for PDFs.
      programs.zathura.enable = true;
      home.packages = [
        pkgs.gdu
        pkgs.zed-delta
        antigravity-hub
        # Zed's editor and terminal fonts; the Macs take them from the base cask list.
        pkgs.jetbrains-mono
        pkgs.nerd-fonts.jetbrains-mono
      ];
    };
}
