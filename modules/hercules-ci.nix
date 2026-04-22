# Flake-level effects framework scaffolding (M2 — mission ADR-001).
#
# Imports the `hercules-ci-effects` flake-parts module so that the
# top-level flake output `herculesCI` is wired to the schema consumed
# by buildbot-nix (`flake.outputs.herculesCI(args).onPush.default.outputs.effects`,
# per `buildbot-nix/buildbot_effects/buildbot_effects/__init__.py:142-159`).
#
# At this milestone no effects are declared yet — the attribute is
# explicitly set to an empty attrset so the eval surface is well-formed
# for downstream buildbot-nix consumption. Per-job effects land in M4
# under this same `onPush.default.outputs.effects.<name>` path.
#
# See `docs/notes/development/ci-cd/decisions/ADR-001-cd-to-buildbot-migration.md`
# for the full rationale and the fixed-attribute-path contract.
{ inputs, ... }:
{
  imports = [
    inputs.hercules-ci-effects.flakeModule
  ];

  # Empty but well-formed `herculesCI` function. The `onPush.default.outputs.effects`
  # key is materialized as an empty attrset so `buildbot-effects list` returns `[]`
  # rather than an error when the master evaluates this flake.
  herculesCI =
    { ... }:
    {
      onPush.default.outputs.effects = { };
    };
}
