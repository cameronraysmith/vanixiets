# Custom lib extensions
# Provides:
# - mdFormat: type for markdown documents with frontmatter (used by agents-md)
# - userIdentities: SSH keys for user identities (single source of truth)
{ lib, ... }:
{
  flake.lib = {
    # User identity SSH keys - single source of truth
    # All machine configs and clan inventory modules reference these keys.
    # Add new keys here; they propagate everywhere automatically.
    userIdentities = {
      # crs58/cameron identity (same person, different usernames per machine)
      # - crs58: legacy username on stibnite, blackphos
      # - cameron: preferred username on newer machines (argentum, rosegold, nixos servers)
      crs58 = {
        sshKeys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdO9rInDa9HvdtZZxmkgeEdAlTupCy3BgA/sqSGyUH+"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFXI36PvOzvuJQKVXWbfQE7Mdb6avTKU1+rV1kgy8tvp pixel7-termux"
        ];
      };

      # raquel: primary user on blackphos
      raquel = {
        sshKeys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAIBdSMsU0hZy7MPpnFmS+P7RlN/x6GwMPVp3g7BOUuf"
        ];
      };

      # christophersmith: primary user on argentum
      christophersmith = {
        sshKeys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKPi1aUkaTAykqzTEQI1lr8qTpPMxXcyxZwilVECIzAM"
        ];
      };

      # janettesmith: primary user on rosegold
      janettesmith = {
        sshKeys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIePSVx5J/JJ5eN4PSryuL7iP8WXow/SsZOIr96qnKP0"
        ];
      };
    };
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
