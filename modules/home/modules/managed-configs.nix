# managedConfigs: configuration files an application also writes at runtime,
# kept as real files so a runtime write never replaces a store symlink.
#
# Each entry is rewritten every activation as its declared `settings` plus the
# `appOwned` key paths copied from the existing file; every other key the file
# had is dropped and reported by name. Key paths are dotted strings, so keys
# containing dots cannot be addressed.
{ ... }:
let
  program =
    pkgs:
    pkgs.writeShellApplication {
      name = "managed-config";
      runtimeInputs = [
        pkgs.yq-go
        pkgs.jq
        pkgs.coreutils
      ];
      text = builtins.readFile ./managed-config.sh;
    };
in
{
  flake.lib.managedConfigProgram = program;

  flake.modules.homeManager.managedConfigs =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.managedConfigs;
      jsonFormat = pkgs.formats.json { };

      specFile =
        name: entry:
        pkgs.writeText "managed-config-${name}.json" (
          builtins.toJSON {
            inherit name;
            inherit (entry)
              target
              format
              fileMode
              appOwned
              externalPaths
              ;
            declared = jsonFormat.generate "managed-config-${name}-declared.json" entry.settings;
          }
        );

      # An appOwned path collides with the declaration when it names a declared
      # node or descends through a declared non-attrset value.
      appOwnedConflicts =
        settings: path:
        let
          segments = lib.splitString "." path;
          throughLeaf = lib.any (
            n:
            let
              prefix = lib.take n segments;
            in
            lib.hasAttrByPath prefix settings && !lib.isAttrs (lib.getAttrFromPath prefix settings)
          ) (lib.range 1 (lib.length segments - 1));
        in
        lib.hasAttrByPath segments settings || throughLeaf;

      homeFileTargets = lib.mapAttrsToList (
        _: file:
        if lib.hasPrefix "/" file.target then file.target else "${config.home.homeDirectory}/${file.target}"
      ) (lib.filterAttrs (_: file: file.enable) config.home.file);
    in
    {
      key = "vanixiets/managed-configs";

      options.managedConfigs = lib.mkOption {
        default = { };
        description = ''
          Files written each activation as `settings` plus the `appOwned` key
          paths kept from the existing file; all other existing keys are
          dropped and reported by name on stderr.
        '';
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              target = lib.mkOption {
                type = lib.types.str;
                description = "Absolute path of the managed file.";
              };
              format = lib.mkOption {
                type = lib.types.enum [
                  "json"
                  "yaml"
                  "toml"
                ];
                description = "Serialization of the managed file.";
              };
              settings = lib.mkOption {
                inherit (jsonFormat) type;
                description = "Declared content of the file.";
              };
              appOwned = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = ''
                  Dotted key paths whose values are kept from the existing file
                  when present there. A non-empty list makes an unreadable or
                  non-mapping target an activation error instead of being replaced.
                '';
              };
              externalPaths = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = ''
                  Dotted key paths another activation step rewrites after this
                  one; keys under them are not reported as dropped.
                '';
              };
              fileMode = lib.mkOption {
                type = lib.types.str;
                default = "0644";
                description = "Mode of the written file.";
              };
              replacesHomeFile = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = ''
                  `home.file` attribute name another module renders for the same
                  file; that entry is disabled.
                '';
              };
            };
          }
        );
      };

      config = lib.mkIf (cfg != { }) {
        home.activation.managedConfigs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run ${lib.getExe (program pkgs)} ${lib.escapeShellArgs (lib.mapAttrsToList specFile cfg)}
        '';

        home.file = lib.mapAttrs' (
          _: entry:
          lib.nameValuePair entry.replacesHomeFile {
            enable = lib.mkForce false;
          }
        ) (lib.filterAttrs (_: entry: entry.replacesHomeFile != null) cfg);

        assertions = lib.concatLists (
          lib.mapAttrsToList (name: entry: [
            {
              assertion = lib.hasPrefix "/" entry.target;
              message = "managedConfigs.${name}.target must be absolute, got ${entry.target}";
            }
            {
              assertion = !lib.any (appOwnedConflicts entry.settings) entry.appOwned;
              message = "managedConfigs.${name}: appOwned paths overlap declared settings: ${lib.concatStringsSep ", " (lib.filter (appOwnedConflicts entry.settings) entry.appOwned)}";
            }
            {
              assertion = !lib.elem entry.target homeFileTargets;
              message = "managedConfigs.${name}: ${entry.target} is also an enabled home.file target";
            }
          ]) cfg
        );
      };
    };
}
