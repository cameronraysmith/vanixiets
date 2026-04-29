# nix-unit invariants for flake.lib.mdFormat (modules/lib/md-format.nix).
#
# The submodule's `text` output is a string built by module-system merging
# of `metadata` (JSON) and `body` (lines) into a frontmatter+body shape.
# Catches silent regressions in either branch (empty vs non-empty metadata)
# that would otherwise produce wrong-looking AGENTS.md files without
# failing any build.
{ config, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      checks.eval-md-format = config.flake.lib.mkEvalCheck pkgs {
        name = "md-format";
        testFile = pkgs.writeText "md-format.tests.nix" ''
          let
            lib = import ${pkgs.path}/lib;
            mdFormatType = (import ${./md-format.nix} { inherit lib; }).flake.lib.mdFormat;

            evalMd =
              data:
              (lib.evalModules {
                modules = [
                  { options.it = lib.mkOption { type = mdFormatType; }; }
                  { it = data; }
                ];
              }).config.it;
          in
          {
            testEmptyMetadataPassesBodyThrough = {
              expr = (evalMd { body = "hello"; }).text;
              expected = "hello";
            };

            testNonEmptyMetadataWrapsAsFrontmatter = {
              expr = (evalMd {
                metadata.title = "AGENTS";
                metadata.priority = 1;
                body = "world";
              }).text;
              expected = '''
                ---
                {"priority":1,"title":"AGENTS"}
                ---

                world
              ''';
            };
          }
        '';
      };
    };
}
