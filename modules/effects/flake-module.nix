# Lifts the hercules-ci-effects flake-parts module to repo-agnostic scope so
# per-repo effect domains under modules/effects/<repo>/herculesCI/*.nix can
# merge into herculesCI.onPush.default.outputs.effects.<name> without each
# domain re-importing the flakeModule.
{ inputs, ... }:
{
  imports = [
    inputs.hercules-ci-effects.flakeModule
  ];
}
