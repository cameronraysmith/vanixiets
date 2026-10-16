{ config, ... }:
let
  flakeConfig = config;
in
{
  flake.modules.darwin.shared-reference-tree =
    { ... }:
    {
      imports = [ flakeConfig.flake.modules.darwin.shared-reference-tree-options ];
    };
}
