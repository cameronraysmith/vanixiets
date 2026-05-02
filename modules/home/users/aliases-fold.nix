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
      # mkForce on identity setters: the canonical default identity (synthesized
      # in `users/lib.nix` from the attribute key) sets
      # `home.username = lib.mkDefault "<target>"` while the alias record
      # needs the alias name. mkForce overrides the inherited mkDefault.
      # mkForce on `home.homeDirectory` is the sole setter for the alias
      # path, since the canonical homeDirectory derives self-referentially
      # from `config.home.username`.
      identity = config.flake.lib.mkUserIdentity {
        user = alias;
        force = true;
      };
    }
  ) config.flake.userAliases;
}
