{ config, ... }:
let
  flakeConfig = config;
in
{
  flake.modules.nixos.shared-reference-tree =
    { ... }:
    {
      imports = [ flakeConfig.flake.modules.nixos.shared-reference-tree-options ];
    };
}
