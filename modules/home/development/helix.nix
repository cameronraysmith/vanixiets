{ ... }:
{
  flake.modules.homeManager.development =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      options = {
        my.helix = {
          markdown.enable = lib.mkEnableOption "Enable markdown support" // {
            # Disabled: marksman requires dotnet which requires Swift.
            # Swift has not been cached on Hydra for aarch64-darwin since Dec 30, 2025.
            # Monitor build status:
            #   https://hydra.nixos.org/job/nixpkgs/trunk/swiftPackages.swift.aarch64-darwin
            #   https://hydra.nixos.org/job/nixpkgs/trunk/marksman.aarch64-darwin
            default = false;
          };
        };
      };

      config.programs.helix = {
        enable = true;
        extraPackages = lib.optional config.my.helix.markdown.enable pkgs.marksman;
        settings = {
          editor.true-color = true;
          keys = {
            insert.j.j = "normal_mode";
            # Shortcut to save file, in any mode.
            insert."C-s" = [
              ":write"
              "normal_mode"
            ];
            normal."C-s" = ":write";
          };

          editor.lsp = {
            display-messages = true;
            display-inlay-hints = true;
            display-signature-help-docs = true;
          };
        };
      };
    };
}
