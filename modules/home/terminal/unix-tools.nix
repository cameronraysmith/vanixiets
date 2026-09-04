{ ... }:
{
  flake.modules.homeManager.terminal =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        b3sum
        coreutils # many (non-)overlapping tools in toybox
        diskus
        fd
        findutils # mostly covered by alternatives in toybox
        gnugrep # alternative in toybox
        gnupatch # alternative in toybox
        gnupg
        gnused # alternative in toybox
        gum
        moreutils
        patchutils
        pinentry-tty
        pipe-rename
        procps # mostly covered by alternatives in toybox
        procs # alternative to ps
        rename
        ripgrep
        rsync
        sd
        sesh
        # toybox # many (non-)overlapping tools in coreutils + grep/sed/find/xargs/ps
        trash-cli
        fuc
        rip2
        tree
        unison
      ];
    };
}
