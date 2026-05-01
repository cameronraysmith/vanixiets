{
  # OUTER: Flake-parts module
  ...
}:
let
  content =
    {
      # INNER: Home-manager module
      pkgs,
      flake, # from extraSpecialArgs
      ...
    }:
    {
      # Portable content: secret-free, identity-independent.
      # Available to home-trial alongside the same aggregate selection.

      home.stateVersion = "23.11";

      home.packages =
        with pkgs;
        [
          gh # GitHub CLI (keep from baseline)
        ]
        ++ [
          flake.inputs.niks3.packages.${pkgs.stdenv.hostPlatform.system}.niks3
        ];
    };
in
{
  flake.modules.homeManager."portable/crs58" = content;
  flake.users.crs58.contentPortable = content;
}
