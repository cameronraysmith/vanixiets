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
  version = "0.13.0";

  src = fetchFromGitHub {
    owner = "Dicklesworthstone";
    repo = "beads_viewer";
    rev = "v${version}";
    hash = "sha256-lFJPZFeXnhLhfGvZybpSJOi/11xcaP8bn+6KpxljlPM=";
  };

  vendorHash = "sha256-V8Bl5lW9vd7o1ZcQ6rvs3WJ1ueYX7xKnHTyRAASHlng=";

  subPackages = [ "cmd/bv" ];

  # Upstream forgot to bump version constant for v0.13.0 (still says v0.12.1)
  postPatch = ''
    sed -i 's/var Version = "v[^"]*"/var Version = "v${version}"/' pkg/version/version.go
  '';

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
