# flake.userAliases names, for a person known by two names, the account the
# fleet's per-person records use (cameron is the account crs58). Both
# directions of that correspondence are defined here, beside the table:
# accountOf maps a person to their account and personOf an account to the
# person, and nothing else restates either.
{ config, lib, ... }:
let
  inherit (config.flake) userAliases users;
in
{
  options.flake.userAliases = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
    description = ''
      Map from alias name to existing user shortname (a key under `flake.users`).
      Each alias produces an additional `homeConfigurations` entry that builds
      the aliased user's full content with `home.username` overridden to the
      alias name.

      Example: `{ cameron = "crs58"; }` causes `homeConfigurations.cameron@<system>`
      to be built from crs58's content with `home.username = "cameron"`.
    '';
  };

  config.flake.userAliases = {
    # cameron is the same human as crs58, with the username "cameron" preferred
    # on newer machines (argentum, rosegold, NixOS servers) and "crs58" forced
    # on legacy machines (stibnite, blackphos) due to historical account names.
    cameron = "crs58";
  };

  # A person's account: the alias target where the name is an alias, else
  # the name itself (cameron -> crs58).
  config.flake.lib.accountOf = name: userAliases.${name} or name;

  # An account's person: the one flake.userAliases key naming it, else the
  # name itself when it is a flake user or alias (crs58 -> cameron). Any
  # other name fails evaluation rather than return a name the fleet does
  # not know.
  config.flake.lib.personOf =
    name:
    let
      aliases = lib.attrNames (lib.filterAttrs (_: target: target == name) userAliases);
    in
    if lib.length aliases == 1 then
      lib.head aliases
    else if aliases != [ ] then
      throw "flake.lib.personOf: user ${name} is the target of several flake.userAliases (${lib.concatStringsSep ", " aliases}); name the person explicitly."
    else if users ? ${name} || userAliases ? ${name} then
      name
    else
      throw "flake.lib.personOf: user ${name} is neither a flake.users key nor a flake.userAliases key; name the person explicitly rather than use an unknown name.";
}
