# Pin fish to stable darwin release channel on darwin machines
# Workaround for failing fish tests in unstable nixpkgs
{ ... }:
{
  flake.nixpkgsOverlays = [
    (
      final: prev:
      if prev.stdenv.isDarwin then
        {
          fish = prev.stable.fish;
        }
      else
        { }
    )
  ];
}
