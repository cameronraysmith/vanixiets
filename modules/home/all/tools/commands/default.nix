{
  pkgs,
  lib,
  config,
  ...
}:
let
  # Helper to create shell applications from either:
  # - Simple string (text only)
  # - Attribute set with optional runtimeInputs, bashOptions, etc.
  makeShellApp =
    name: config:
    let
      normalized = if lib.isString config then { text = config; } else config;
    in
    pkgs.writeShellApplication (normalized // { inherit name; });

  # Import descriptions metadata
  descriptions = import ./descriptions.nix;

  # Generate formatted reference text by category
  generateReference =
    let
      # Sort categories by order
      sortedCategories = lib.sort (a: b: a.order < b.order) descriptions.categories;

      # Format a single category
      formatCategory =
        category:
        let
          # Get commands sorted alphabetically
          commandNames = lib.sort (a: b: a < b) (lib.attrNames category.commands);

          # Format each command as "name    description"
          formatCommand =
            name:
            let
              # Pad command name to 32 chars for alignment
              paddedName = lib.fixedWidthString 32 " " name;
            in
            "${paddedName} ${category.commands.${name}}";

          commandLines = map formatCommand commandNames;
        in
        # Category header + commands
        [ "# ${category.name}" ] ++ commandLines ++ [ "" ];

      # Generate all sections
      allSections = lib.concatMap formatCategory sortedCategories;

      # Remove trailing empty line
      lines = lib.init allSections;
    in
    lib.concatStringsSep "\n" lines;

  # Import all command categories and merge
  allCommands =
    (import ./git-tools.nix { inherit pkgs lib config; })
    // (import ./nix-tools.nix { inherit pkgs lib config; })
    // (import ./file-tools.nix { inherit pkgs lib config; })
    // (import ./dev-tools.nix { inherit pkgs lib config; })
    // {
      # nsa-ref command with dynamically generated content
      nsa-ref = {
        text = ''
          case "''${1:-}" in
            -h|--help)
              cat <<'HELP'
          List all nix shell applications with descriptions

          Usage: nsa-ref

          Displays a reference list of all available shell commands
          defined in this configuration, organized by category.

          Example:
            nsa-ref    # Show all commands and descriptions
          HELP
              exit 0
              ;;
          esac

          cat <<'EOF'
          ${generateReference}
          EOF
        '';
      };
    };
in
{
  home.packages =
    # Bash shell applications using writeShellApplication
    (lib.mapAttrsToList makeShellApp allCommands)
    # Nushell shell applications using nuenv.writeShellApplication
    ++ [ pkgs.atuin-format ];
}
