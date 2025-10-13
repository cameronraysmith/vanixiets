{ inputs }:
let
  inherit (inputs.nixpkgs) lib;
in
rec {
  # EXISTING: mdFormat helper (preserve exact implementation)
  mdFormat = lib.types.submodule (
    { config, ... }:
    {
      options = {
        metadata = lib.mkOption {
          type =
            with lib.types;
            let
              valueType =
                nullOr (oneOf [
                  bool
                  int
                  float
                  str
                  path
                  (attrsOf valueType)
                  (listOf valueType)
                ])
                // {
                  description = "JSON value";
                };
            in
            valueType;
          default = { };
          description = "Frontmatter for the markdown file, written as YAML.";
        };
        body = lib.mkOption {
          type = lib.types.lines;
          description = "Markdown content for the file.";
        };
        text = lib.mkOption {
          type = lib.types.str;
          readOnly = true;
        };
      };
      config = {
        text =
          if config.metadata == { } then
            config.body
          else
            ''
              ---
              ${lib.strings.toJSON config.metadata}
              ---

              ${config.body}
            '';
      };
    }
  );

  # NEW: Select appropriate nixpkgs input based on OS and channel
  # Example: systemInput { name = "nixpkgs"; channel = "stable"; os = "darwin"; }
  # Returns: inputs.nixpkgs-darwin-stable (or falls back to inputs.nixpkgs)
  systemInput =
    {
      name,
      channel,
      os,
    }:
    inputs."${name}-${os}-${channel}" or inputs.${name};

  # NEW: Extract OS from system string
  # Example: systemOs "aarch64-darwin" → "darwin"
  # Example: systemOs "x86_64-linux" → "linux"
  systemOs = system: lib.last (lib.splitString "-" system);

  # NEW: Import all overlays from a directory
  # Excludes: _*.nix, default.nix
  # Imports: directories with default.nix as the directory name
  # Used for overlays/overrides/ pattern in Phase 2
  importOverlays =
    dir: final: prev:
    let
      filterPath =
        name: type:
        !lib.hasPrefix "_" name && type == "regular" && lib.hasSuffix ".nix" name && name != "default.nix";
      dirContents = builtins.readDir dir;
      filteredContents = lib.filterAttrs filterPath dirContents;
      filteredPaths = builtins.attrNames filteredContents;
      importedOverlays = lib.listToAttrs (
        map (name: {
          name = lib.removeSuffix ".nix" name;
          value = import (dir + "/${name}") final prev;
        }) filteredPaths
      );
      importedDefaultOverlay =
        if lib.pathExists (dir + "/default.nix") then import (dir + "/default.nix") final prev else { };
    in
    importedDefaultOverlay // importedOverlays;
}
