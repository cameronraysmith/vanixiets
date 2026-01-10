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
  version = "0.12.1";

  src = fetchFromGitHub {
    owner = "Dicklesworthstone";
    repo = "beads_viewer";
    rev = "v${version}";
    hash = "sha256-qesp5gwR9zlPpmq5BXW110Ab1KJ0M+v8VZJk1AxFw2w=";
  };

  vendorHash = "sha256-rtIqTK6ez27kvPMbNjYSJKFLRbfUv88jq8bCfMkYjfs=";

  subPackages = [ "cmd/bv" ];

  # Ensure version constant matches derivation version
  postPatch = ''
    sed -i 's/const Version = "v[^"]*"/const Version = "v${version}"/' pkg/version/version.go
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
