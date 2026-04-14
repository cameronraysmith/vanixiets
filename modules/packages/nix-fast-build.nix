{ inputs, ... }:
{
  perSystem =
    { system, ... }:
    {
      packages.nix-fast-build = inputs.nix-fast-build.packages.${system}.default;
    };
}
