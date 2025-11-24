{ inputs, ... }:
{
  imports = [
    inputs.clan-core.flakeModules.default
    inputs.terranix.flakeModule
  ];
}
