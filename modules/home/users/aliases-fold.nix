# Materialize each entry of `flake.userAliases` into a `flake.users.<alias>`
# record by copying the target user's meta and aggregates, with the alias
# name substituted into `meta.username`. Keeps `flake.userAliases` as the
# single source of truth for the alias relationship while making the alias
# visible to any consumer that reads `flake.users.<u>` uniformly (e.g.
# capability aggregates that look up `flake.users.${config.home.username}.meta`).
{
  config,
  lib,
  ...
}:
{
  config.flake.users = lib.mapAttrs' (
    alias: target:
    lib.nameValuePair alias {
      meta = config.flake.users.${target}.meta // {
        username = alias;
      };
      aggregates = config.flake.users.${target}.aggregates;
      contentPrivate = config.flake.users.${target}.contentPrivate;
      contentPortable = config.flake.users.${target}.contentPortable;
      # mkForce on `home.username` is required: the target user's content
      # module sets `home.username = lib.mkDefault target.meta.username`
      # ("crs58") while identity-fold synthesizes
      # `home.username = lib.mkDefault meta.username` ("cameron" for the
      # alias record) — two mkDefaults at priority 1000 with different
      # values would be a defining-multiple-times error. mkForce
      # (priority 50) breaks the tie. mkForce on `home.homeDirectory`
      # is defense-in-depth: under current code the homeDirectory derives
      # from `config.home.username` self-referentially, so mkForcing the
      # username already pins the directory; the explicit mkForce here
      # preserves the invariant against future code changes.
      identityOverride =
        {
          config,
          pkgs,
          ...
        }:
        {
          home.username = lib.mkForce alias;
          home.homeDirectory = lib.mkForce (
            if pkgs.stdenv.isDarwin then "/Users/${alias}" else "/home/${alias}"
          );
        };
    }
  ) config.flake.userAliases;
}
