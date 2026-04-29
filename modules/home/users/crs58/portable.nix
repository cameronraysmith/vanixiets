{
  # OUTER: Flake-parts module
  ...
}:
{
  flake.modules.homeManager."portable/crs58" =
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
}
