# gastown - Multi-agent orchestration framework
#
# Coordinates AI agents (particularly Claude Code) working across
# distributed software projects, supporting 20-30+ simultaneous agents.
#
# Source: https://github.com/steveyegge/gastown
#
# Binary name: upstream uses `gt`, which is preserved here.
# graphite-cli (also uses `gt`) is renamed to `grt` via overlay.
# See: modules/nixpkgs/overlays/overrides.nix
{
  lib,
  buildGoModule,
  fetchFromGitHub,
  nix-update-script,
  versionCheckHook,
}:

buildGoModule (finalAttrs: {
  pname = "gastown";
  # To switch back to tagged release: version = "0.2.1"; and use tag instead of rev
  version = "unstable-2026-01-05";

  src = fetchFromGitHub {
    owner = "steveyegge";
    repo = "gastown";
    rev = "6e4f2bea299521b0b32a7ad642117d3d6b96ca3c";
    # tag = "v${finalAttrs.version}";
    hash = "sha256-Cy6B/pWf7SjhlrWgH3nMZMKButiXSna01VZZkOWwkzA=";
  };

  vendorHash = "sha256-L+Hj2pCsqKX/6MXNq5P33RPOAbxvrLgsbNDIRdNTvvw=";

  subPackages = [ "cmd/gt" ];

  ldflags = [
    "-s"
    "-w"
    "-X=github.com/steveyegge/gastown/internal/cmd.Version=${finalAttrs.version}"
    "-X=github.com/steveyegge/gastown/internal/cmd.Build=nix"
  ];

  # Tests require git worktrees, tmux, and other runtime dependencies
  doCheck = false;

  # Version check disabled for unstable builds; re-enable for tagged releases
  # nativeInstallCheckInputs = [ versionCheckHook ];
  # versionCheckProgram = "${placeholder "out"}/bin/gt";
  # versionCheckProgramArg = "version";
  # doInstallCheck = true;

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Multi-agent orchestration framework for coordinating AI agents across distributed projects";
    longDescription = ''
      Gastown provides infrastructure for scaling from a few AI agents to 20-30+
      working simultaneously across software projects. Features include:

      - Work persistence through crashes/restarts
      - Structured agent identity and attribution
      - Autonomous execution (propulsion principle)
      - Inter-agent coordination via mail system
      - Workspace hierarchy: Town → Rig → Agents
      - Agent roles: Mayor, Witness, Refinery, Polecat, Crew
      - Convoy tracking for batched work across rigs
      - Molecule workflow templates with phase states
    '';
    homepage = "https://github.com/steveyegge/gastown";
    changelog = "https://github.com/steveyegge/gastown/blob/main/CHANGELOG.md";
    license = lib.licenses.mit;
    mainProgram = "gt";
    platforms = lib.platforms.unix;
  };
})
