{ ... }:
{
  flake.modules.homeManager.tools =
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
      descriptions = import ./_descriptions.nix;

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
        (import ./_git-tools.nix { inherit pkgs lib config; })
        // (import ./_nix-tools.nix { inherit pkgs lib config; })
        // (import ./_file-tools.nix { inherit pkgs lib config; })
        // (import ./_dev-tools.nix { inherit pkgs lib config; })
        // (import ./_system-tools.nix { inherit pkgs lib config; })
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
        (lib.mapAttrsToList makeShellApp allCommands);
      # TODO: Requires atuin-format package from infra overlays
      # Located at: infra/overlays/packages/atuin-format/package.nix
      # Temporarily disabled until overlay is migrated
      # Nushell shell applications using nuenv.writeShellApplication
      # ++ [ pkgs.atuin-format ];
    };
}
