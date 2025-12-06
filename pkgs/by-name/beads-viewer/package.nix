# beads_viewer (bv) - TUI for beads issue tracker
#
# High-performance terminal UI for browsing and managing tasks in projects
# that use the Beads issue tracking system. Features dependency graph analysis,
# Kanban board view, and AI agent robot protocol.
#
# Source: https://github.com/Dicklesworthstone/beads_viewer
{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule rec {
  pname = "beads-viewer";
  version = "0.10.2";

  src = fetchFromGitHub {
    owner = "Dicklesworthstone";
    repo = "beads_viewer";
    rev = "v${version}";
    hash = "sha256-GteCe909fpjjiFzjVKUY9dgfU7ubzue8vDOxn0NEt/A=";
  };

  vendorHash = "sha256-yhwokKjwDe99uuTlRtyoX4FeR1/RZEu7J0PMdAVrows=";

  subPackages = [ "cmd/bv" ];

  # Tests require beads fixtures and git history
  doCheck = false;

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
