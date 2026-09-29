# hercules-ci-effects' herculesCI module declares onPush and onSchedule and
# returns nothing else; nixbot additionally reads `onEvent` from the same
# value (event effects, evaluated from the default branch). The option lives
# here so every onEvent effect file contributes to one declaration.
{ inputs, lib, ... }:
{
  imports = [
    inputs.hercules-ci-effects.flakeModule
  ];

  herculesCI =
    { config, ... }:
    {
      options.onEvent = lib.mkOption {
        type = lib.types.lazyAttrsOf (lib.types.lazyAttrsOf lib.types.raw);
        default = { };
        description = "nixbot event effects, keyed by event kind then effect name.";
      };
      config.out.onEvent = config.onEvent;
    };
}
