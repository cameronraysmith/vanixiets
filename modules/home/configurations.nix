{
  config,
  lib,
  ...
}:
let
  # Auto-discover users that have opted in by setting a non-empty aggregates list.
  # Users with `aggregates = [ ]` (today: christophersmith, janettesmith, tara) are
  # not emitted in homeConfigurations until they opt in.
  enumerableUsers = lib.filterAttrs (_: u: u.aggregates != [ ]) config.flake.users;
  enumerableUserNames = lib.attrNames enumerableUsers;

  # Direct entries: homeConfigurations."<user>@<system>"
  userEntries = lib.listToAttrs (
    lib.concatMap (
      user:
      map (system: {
        name = "${user}@${system}";
        value = config.flake.lib.mkHome {
          inherit user system;
        };
      }) config.systems
    ) enumerableUserNames
  );

  # Alias entries: homeConfigurations."<alias>@<system>" built from the
  # alias's own materialized user record (see aliases-fold.nix). Aliases
  # follow the same enumeration rule as direct users — only emitted when
  # their target user has non-empty aggregates.
  aliasEntries = lib.listToAttrs (
    lib.concatMap (
      { name, value }:
      let
        targetUser = value;
        aliasName = name;
      in
      lib.optionals (lib.elem targetUser enumerableUserNames) (
        map (system: {
          name = "${aliasName}@${system}";
          value = config.flake.lib.mkHome {
            user = aliasName;
            inherit system;
          };
        }) config.systems
      )
    ) (lib.attrsToList config.flake.userAliases)
  );
in
{
  # Flat-tuple shape: homeConfigurations."<user>@<system>"
  # Compatible with flake-schemas (one-level walk) and home-manager CLI's
  # explicit `--flake .#<user>@<system>` invocation.
  flake.homeConfigurations = userEntries // aliasEntries;
}
