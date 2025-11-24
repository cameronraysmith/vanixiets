# markdown-tree-parser npm package
#
# Dendritic flake-parts module exporting markdown-tree-parser overlay
#
# CLI tool for parsing and manipulating markdown files as tree structures
# Source: https://github.com/ksylvan/markdown-tree-parser
#
{ ... }:
{
  flake.nixpkgsOverlays = [
    (final: prev: {
      markdown-tree-parser = prev.callPackage (
        {
          lib,
          buildNpmPackage,
          fetchFromGitHub,
        }:
        buildNpmPackage rec {
          pname = "markdown-tree-parser";
          version = "1.6.1";

          src = fetchFromGitHub {
            owner = "ksylvan";
            repo = "markdown-tree-parser";
            rev = "v${version}";
            hash = "sha256-r6c6tpk7R2pWNJmRyIS1ScfX2L6nTVorOXNrGByJpgE=";
          };

          npmDepsHash = "sha256-2oDTln7l03RHk/uOP8vEOeOc9kO5ezXnMBEQYMVoNEo=";

          dontNpmBuild = true;

          meta = {
            description = "A powerful JavaScript library and CLI tool for parsing and manipulating markdown files as tree structures";
            homepage = "https://github.com/ksylvan/markdown-tree-parser";
            license = lib.licenses.mit;
            mainProgram = "md-tree";
            platforms = lib.platforms.all;
          };
        }
      ) { };
    })
  ];
}
