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
    {
      pkgs,
      lib,
      system,
      ...
    }:
    let
      check = config.flake.lib.mkEvalCheck pkgs {
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
    in
    {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # nixbot: median 6.5 s, slowest 12 s, 9 runs in 30 days
        eval-md-format.class = "small";
      };
      checks = lib.optionalAttrs (system == "x86_64-linux") { eval-md-format = check; };
    };
}
