# Custom lib extensions
# Provides mdFormat type for markdown documents with frontmatter
# Used by agents-md module to generate AI agent configuration files
{ lib, ... }:
{
  flake.lib = {
    # mdFormat helper for markdown files with YAML frontmatter
    # Type: submodule with metadata (YAML frontmatter) and body (markdown content)
    # Output: text attribute containing formatted markdown with frontmatter
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
  };
}
