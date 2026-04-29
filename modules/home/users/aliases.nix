{ lib, ... }:
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
}
