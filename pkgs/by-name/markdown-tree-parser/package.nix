# markdown-tree-parser npm package
#
# CLI tool for parsing and manipulating markdown files as tree structures
# Source: https://github.com/ksylvan/markdown-tree-parser
#
# pin.json pins the version, the source hash and the npm dependency hash;
# Renovate proposes releases from GitHub and
# `nix run .#realize-pin -- markdown-tree-parser <version>` realizes one.
{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:
let
  inherit
    ((import ../../../lib/pins.nix { inherit lib; }).load ./pin.json { name = "markdown-tree-parser"; })
    pin
    pinPlan
    ;
  planned = (pinPlan pin.version).artifacts;
  inherit (pin.artifacts.src) sourceBuild;
in
buildNpmPackage {
  pname = "markdown-tree-parser";
  inherit (pin) version;

  # The plan's release tag passed as `rev`, as before the pin: `tag` would
  # fetch archive/refs/tags/<tag> and change every drvPath for the same source.
  src =
    let
      inherit (planned.src.sourceBuild.fetchFromGitHub) owner repo tag;
    in
    fetchFromGitHub {
      inherit owner repo;
      rev = tag;
      inherit (sourceBuild) hash;
    };

  npmDepsHash = sourceBuild.depsHash.npm.hash;

  dontNpmBuild = true;

  passthru = {
    inherit pin pinPlan;
  };

  meta = {
    description = "A powerful JavaScript library and CLI tool for parsing and manipulating markdown files as tree structures";
    homepage = "https://github.com/ksylvan/markdown-tree-parser";
    license = lib.licenses.mit;
    mainProgram = "md-tree";
    platforms = lib.platforms.all;
  };
}
