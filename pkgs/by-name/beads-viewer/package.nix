# beads_viewer (bv) - TUI for beads issue tracker
#
# TUI for browsing and managing tasks in projects
# that use the `beads` issue tracking system.
#
# Source: https://github.com/Dicklesworthstone/beads_viewer
{
  lib,
  buildGoModule,
  fetchFromGitHub,
  nix-update-script,
  versionCheckHook,
}:

buildGoModule rec {
  pname = "beads-viewer";
  version = "0.14.4";

  src = fetchFromGitHub {
    owner = "Dicklesworthstone";
    repo = "beads_viewer";
    rev = "v${version}";
    hash = "sha256-0HK1ycgE9U57mYLhOgR68ElWQWXin4v5P7l1n4XECI8=";
  };

  vendorHash = null;

  subPackages = [ "cmd/bv" ];

  # Tests require fixtures and git history
  doCheck = false;

  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgramArg = "--version";
  doInstallCheck = true;

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "High-performance TUI for the Beads issue tracker with dependency graph analysis";
    longDescription = ''
      bv (Beads Viewer) is an elegant, keyboard-driven terminal interface for the
      Beads issue tracker. It visualizes projects as dependency graphs, computing
      PageRank, Betweenness centrality, HITS scores, and critical paths to surface
      hidden project dynamics. Features include Kanban board view, time-travel
      diffing against git history, and a robot protocol for AI agent integration.
    '';
    homepage = "https://github.com/Dicklesworthstone/beads_viewer";
    license = lib.licenses.mit;
    mainProgram = "bv";
    platforms = lib.platforms.unix;
  };
}
