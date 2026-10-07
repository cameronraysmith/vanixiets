_: {
  nixpkgsOverlays = [
    # Upstream builds clipboard-jh with gcc15Stdenv on every platform
    # (nixpkgs pkgs/by-name/cl/clipboard-jh/package.nix), but its Darwin
    # sources are Objective-C++ compiled with -fobjc-arc, which GCC does not
    # implement, so the Darwin build fails in src/cb.
    # Darwin's default stdenv is clang, which supports ARC.
    (final: prev: {
      clipboard-jh =
        if prev.stdenv.hostPlatform.isDarwin then
          prev.clipboard-jh.override { gcc15Stdenv = final.stdenv; }
        else
          prev.clipboard-jh;
    })
  ];
}
